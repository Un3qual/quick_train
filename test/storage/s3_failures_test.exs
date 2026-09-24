defmodule QuickTrain.Assets.S3FailuresTest do
  use ExUnit.Case, async: false
  alias QuickTrain.Assets.Storage.S3
  alias QuickTrainWeb.S3FaultServer, as: Server

  @moduletag :storage

  setup_all do
    QuickTrain.S3Fixture.configure()
  end

  setup do
    options = Application.fetch_env!(:quick_train, :s3_storage)
    on_exit(fn -> Application.put_env(:quick_train, :s3_storage, options) end)
    %{options: options, key: "assets/staging/#{Ash.UUID.generate()}/#{Ash.UUID.generate()}"}
  end

  test "redirects and untrusted TLS return sanitized failures", ctx do
    redirect =
      Server.start(fn conn ->
        conn
        |> Plug.Conn.put_resp_header("location", "https://private.invalid/credential")
        |> Plug.Conn.send_resp(307, "secret")
      end)

    Application.put_env(:quick_train, :s3_storage, Keyword.put(ctx.options, :endpoint, redirect))
    assert {:error, :storage_redirect} = S3.write_staging(ctx.key, ["four"], 4, 1_000)

    # The server uses the local CA, which is absent from production system trust.
    assert {:error, %{reason: :storage_request_failed}} =
             S3.HTTPClient.request(:get, redirect, nil, [], timeout: 1_000)
  end

  test "oversized error responses are bounded", ctx do
    endpoint =
      Server.start(fn conn ->
        Plug.Conn.send_resp(conn, 500, String.duplicate("secret", 20_000))
      end)

    Application.put_env(:quick_train, :s3_storage, Keyword.put(ctx.options, :endpoint, endpoint))
    assert {:error, :storage_response_too_large} = S3.write_staging(ctx.key, ["four"], 4, 1_000)
  end

  test "a complete remote write may finish after the caller deadline and retry verifies it",
       ctx do
    parent = self()
    upstream = ctx.options[:endpoint]

    endpoint =
      Server.start(fn conn ->
        if conn.method == "PUT" do
          send(parent, {:remote_waiting, self()})

          receive do
            :finish_remote -> :ok
          after
            5_000 -> raise "test barrier timed out"
          end
        end

        result = Server.forward(conn, upstream)
        send(parent, {:remote_finished, elem(result, 1).status})
        Server.respond(result)
      end)

    Application.put_env(:quick_train, :s3_storage, Keyword.put(ctx.options, :endpoint, endpoint))
    operation = Task.async(fn -> S3.write_staging(ctx.key, ["four"], 4, 250) end)
    assert_receive {:remote_waiting, server}, 2_000
    assert {:error, :storage_deadline_exceeded} = Task.await(operation, 2_000)
    send(server, :finish_remote)
    assert_receive {:remote_finished, 200}, 2_000
    Application.put_env(:quick_train, :s3_storage, ctx.options)
    expected = %{sha256: :crypto.hash(:sha256, "four"), byte_size: 4, media_type: "text/plain"}

    assert {:ok, %{facts: ^expected}} =
             S3.verify_and_publish(
               ctx.key,
               String.replace(ctx.key, "/staging/", "/sealed/"),
               expected,
               5_000
             )
  end

  test "replacing staging after HEAD cannot change the version read or published", ctx do
    bytes = :binary.copy("a", 2 * 1024 * 1024)
    size = byte_size(bytes)
    assert :ok = S3.write_staging(ctx.key, [bytes], size, 5_000)
    parent = self()
    upstream = ctx.options[:endpoint]

    endpoint =
      Server.start(fn conn ->
        result = Server.forward(conn, upstream)

        if conn.method == "HEAD" do
          send(parent, {:selected_version, self()})

          receive do
            :continue -> :ok
          after
            5_000 -> raise "test barrier timed out"
          end
        end

        Server.respond(result)
      end)

    Application.put_env(:quick_train, :s3_storage, Keyword.put(ctx.options, :endpoint, endpoint))
    expected = %{sha256: :crypto.hash(:sha256, bytes), byte_size: size, media_type: "text/plain"}
    sealed = String.replace(ctx.key, "/staging/", "/sealed/")
    operation = Task.async(fn -> S3.verify_and_publish(ctx.key, sealed, expected, 5_000) end)
    assert_receive {:selected_version, server}, 2_000
    # Use the direct gateway for the overwrite while publication retains its configuration.
    Application.put_env(:quick_train, :s3_storage, ctx.options)
    assert :ok = S3.write_staging(ctx.key, [:binary.copy("b", size)], size, 5_000)
    send(server, :continue)
    assert {:ok, %{facts: ^expected}} = Task.await(operation, 6_000)
    assert {:ok, ^expected} = S3.verify_sealed(sealed, expected, 5_000)
  end

  test "a conditional conflict retries and verifies the winning canonical content", ctx do
    assert :ok = S3.write_staging(ctx.key, ["four"], 4, 5_000)
    parent = self()

    endpoint =
      Server.start(fn conn ->
        {conn, response} = Server.forward(conn, ctx.options[:endpoint])

        if conn.method == "PUT" do
          send(parent, {:conditional_put, response.status})
        end

        if conn.method == "PUT" and response.status == 200,
          do: Plug.Conn.send_resp(conn, 409, "conflict"),
          else: Server.respond({conn, response})
      end)

    Application.put_env(:quick_train, :s3_storage, Keyword.put(ctx.options, :endpoint, endpoint))
    expected = %{sha256: :crypto.hash(:sha256, "four"), byte_size: 4, media_type: "text/plain"}
    sealed = String.replace(ctx.key, "/staging/", "/sealed/")
    assert {:ok, %{facts: ^expected}} = S3.verify_and_publish(ctx.key, sealed, expected, 5_000)
    assert_receive {:conditional_put, 200}
    assert_receive {:conditional_put, 412}
    refute_receive {:conditional_put, _status}
  end

  test "persistent conditional conflicts stop after one retry", ctx do
    assert :ok = S3.write_staging(ctx.key, ["four"], 4, 5_000)
    parent = self()

    endpoint =
      Server.start(fn conn ->
        if conn.method == "PUT" do
          send(parent, :conditional_conflict)
          Plug.Conn.send_resp(conn, 409, "conflict")
        else
          conn |> Server.forward(ctx.options[:endpoint]) |> Server.respond()
        end
      end)

    Application.put_env(:quick_train, :s3_storage, Keyword.put(ctx.options, :endpoint, endpoint))
    expected = %{sha256: :crypto.hash(:sha256, "four"), byte_size: 4, media_type: "text/plain"}
    sealed = String.replace(ctx.key, "/staging/", "/sealed/")

    assert {:error, :storage_publication_conflict} =
             S3.verify_and_publish(ctx.key, sealed, expected, 5_000)

    assert_receive :conditional_conflict
    assert_receive :conditional_conflict
    refute_receive :conditional_conflict
  end
end
