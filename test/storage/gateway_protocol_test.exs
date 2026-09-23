defmodule QuickTrain.Storage.GatewayProtocolTest do
  use ExUnit.Case, async: false

  alias QuickTrain.Assets.Storage.S3.LocalSetup

  @moduletag :storage

  # This characterizes the exact provider invariants publication will rely on.
  setup_all do
    context = QuickTrain.S3Fixture.configure()
    Map.merge(context, %{config: context.s3_config.sdk, bucket: context.s3_config.bucket})
  end

  test "local bootstrap permits browser uploads only from configured localhost origins",
       context do
    url =
      URI.to_string(context.s3_config.endpoint) <> "/#{context.bucket}/assets/staging/probe/cors"

    preflight = fn origin ->
      Req.request!(context.request,
        method: :options,
        url: url,
        headers: [
          {"origin", origin},
          {"access-control-request-method", "POST"},
          {"access-control-request-headers", "content-type"}
        ]
      )
    end

    allowed = preflight.("http://localhost:4005")
    assert allowed.status == 200

    assert Req.Response.get_header(allowed, "access-control-allow-origin") == [
             "http://localhost:4005"
           ]

    denied = preflight.("https://untrusted.example")
    assert denied.status == 403
    assert Req.Response.get_header(denied, "access-control-allow-origin") == []
  end

  test "local bootstrap rejects AWS, non-loopback endpoints and non-local CORS origins",
       context do
    storage = context.s3_config

    for target <- [
          %{storage | profile: :aws},
          %{storage | endpoint: %{storage.endpoint | host: "storage.example"}}
        ] do
      assert {:error, :local_storage_required} =
               LocalSetup.run(target, ["http://localhost:4005"])
    end

    for origins <- [[], ["*"], ["https://untrusted.example"]] do
      assert {:error, :invalid_local_cors_origins} =
               LocalSetup.run(storage, origins)
    end
  end

  test "POST accepts the exact file cap and rejects cap plus one", context do
    descriptor = post(context, "assets/staging/probe/cap", 4)
    response = upload(context, descriptor, "four")

    assert response.status in [200, 201, 204],
           "exact-cap upload returned #{response.status}: #{response.body}"

    response = upload(context, descriptor, "fives")
    assert response.status in [400, 403], "oversized upload returned #{response.status}"
    assert request(context, :get, "assets/staging/probe/cap").body == "four"
  end

  test "POST enforces fixed fields, destination and expiry", context do
    descriptor = post(context, "assets/staging/probe/fixed", 4)

    for fields <- [
          Map.delete(descriptor.fields, "Content-Type"),
          Map.put(descriptor.fields, "Content-Type", "text/html"),
          Map.put(descriptor.fields, "key", "assets/sealed/probe/forbidden")
        ] do
      assert upload(context, %{descriptor | fields: fields}, "four").status in [400, 403]
    end

    expired = post(context, "assets/staging/probe/expired", 4, -1)
    assert upload(context, expired, "four").status in [400, 403]

    policy = descriptor.fields["Policy"] |> Base.decode64!() |> Jason.decode!()

    for changed <- [
          Map.put(
            policy,
            "expiration",
            DateTime.to_iso8601(DateTime.add(DateTime.utc_now(), 3600))
          ),
          Map.update!(policy, "conditions", fn conditions ->
            Enum.map(conditions, fn
              ["content-length-range", 0, 4] -> ["content-length-range", 0, 100]
              condition -> condition
            end)
          end)
        ] do
      fields = Map.put(descriptor.fields, "Policy", changed |> Jason.encode!() |> Base.encode64())
      assert upload(context, %{descriptor | fields: fields}, "four").status in [400, 403]
    end
  end

  test "repeated local bootstrap preserves existing bytes and versioning", context do
    key = "assets/staging/probe/versioned"
    assert request(context, :put, key, body: "before").status == 200
    head = request(context, :head, key)
    [version] = Req.Response.get_header(head, "x-amz-version-id")
    refute version in ["", "null"]

    assert :ok =
             LocalSetup.run(context.s3_config, [
               "http://localhost:4005"
             ])

    assert request(context, :get, key).body == "before"
    assert request(context, :put, key, body: "after").status == 200
    [next_version] = Req.Response.get_header(request(context, :head, key), "x-amz-version-id")
    refute next_version in ["", "null", version]
    assert request(context, :get, key, params: [{"versionId", version}]).body == "before"
    assert request(context, :get, key).body == "after"
  end

  test "conditional canonical PUT does not replace existing bytes", context do
    key = "assets/sealed/probe/conditional"
    opts = [headers: [{"if-none-match", "*"}]]
    assert request(context, :put, key, opts ++ [body: "before"]).status == 200
    assert request(context, :put, key, opts ++ [body: "after"]).status == 412
    assert request(context, :get, key).body == "before"
  end

  test "checksum failures cannot install bytes", context do
    key = "assets/staging/probe/checksum"
    checksum = Base.encode64(:crypto.hash(:sha256, "four"))
    opts = [headers: [{"x-amz-checksum-sha256", checksum}]]
    assert request(context, :put, key, opts ++ [body: "five"]).status == 400
    assert request(context, :get, key).status == 404
    assert request(context, :put, key, opts ++ [body: "four"]).status == 200
    assert request(context, :get, key).body == "four"
  end

  test "unsigned reads and writes are denied", context do
    key = "assets/staging/probe/private"
    assert request(context, :put, key, body: "private").status == 200
    url = System.fetch_env!("QUICK_TRAIN_STORAGE_ENDPOINT") <> "/#{context.bucket}/#{key}"
    assert Req.get!(context.request, url: url).status == 403
    assert Req.put!(context.request, url: url, body: "overwrite").status == 403
  end

  defp post(context, key, cap, expires_in \\ 60) do
    fields = %{
      "Content-Type" => "application/octet-stream",
      "Content-Disposition" => "attachment",
      "Cache-Control" => "no-store"
    }

    post =
      ExAws.S3.presigned_post(context.config, context.bucket, key,
        expires_in: expires_in,
        content_length_range: [0, cap],
        custom_conditions: Enum.map(fields, fn {name, value} -> %{name => value} end)
      )

    %{post | fields: Map.merge(post.fields, fields)}
  end

  defp upload(context, descriptor, bytes) do
    Req.post!(context.request,
      url: descriptor.url,
      form_multipart: Map.to_list(descriptor.fields) ++ [{"file", {bytes, filename: "probe.bin"}}]
    )
  end

  defp request(context, method, key, opts \\ []) do
    {:ok, url} =
      ExAws.S3.presigned_url(context.config, method, context.bucket, key,
        expires_in: 60,
        query_params: Keyword.get(opts, :params, []),
        headers: Keyword.get(opts, :headers, [])
      )

    Req.request!(context.request,
      method: method,
      url: url,
      body: Keyword.get(opts, :body),
      headers: Keyword.get(opts, :headers, [])
    )
  end
end
