defmodule QuickTrain.Assets.Storage.S3 do
  @moduledoc "S3 protocol storage with verified immutable publication and bounded local I/O."
  @behaviour QuickTrain.Assets.Storage

  alias QuickTrain.Assets.Storage.S3.{Config, HTTPClient, Operation}

  @download_fields %{
    "Content-Type" => "application/octet-stream",
    "Content-Disposition" => "attachment",
    "Cache-Control" => "no-store"
  }
  @delivery_headers Enum.map(@download_fields, fn {name, value} ->
                      {String.downcase(name), value}
                    end)

  @impl true
  def enforces_byte_cap?, do: match?({:ok, _config}, Config.fetch())

  @impl true
  def approved_hosts do
    case Config.fetch() do
      {:ok, config} -> [config.host]
      {:error, _reason} -> []
    end
  end

  @impl true
  def writable_staging_access(key, cap, expires_at) when is_integer(cap) and cap > 0 do
    with {:ok, config} <- Config.fetch(),
         {:ok, seconds} <- lifetime(expires_at) do
      post =
        ExAws.S3.presigned_post(config.sdk, config.bucket, key,
          expires_in: seconds,
          virtual_host: config.addressing == :virtual,
          content_length_range: [0, cap],
          custom_conditions: Enum.map(@download_fields, fn {name, value} -> %{name => value} end)
        )

      fields = Map.merge(post.fields, @download_fields)
      # Read the SDK's actual policy expiration; never advertise a longer capability.
      policy = fields["Policy"] |> Base.decode64!() |> Jason.decode!()
      {:ok, expiry, 0} = DateTime.from_iso8601(policy["expiration"])

      if DateTime.after?(expiry, expires_at) do
        {:error, :storage_access_expiry_exceeded}
      else
        {:ok,
         descriptor(:post, post.url, expiry)
         |> Map.merge(%{max_bytes: cap, form_fields: fields, file_field: "file"})}
      end
    end
  end

  @impl true
  def sealed_read_access(key, expires_at) do
    with {:ok, config} <- Config.fetch(),
         {:ok, seconds} <- lifetime(expires_at) do
      start = DateTime.utc_now() |> DateTime.truncate(:second)

      query = Enum.map(@delivery_headers, fn {name, value} -> {"response-" <> name, value} end)

      with {:ok, url} <-
             ExAws.S3.presigned_url(config.sdk, :get, config.bucket, key,
               expires_in: seconds,
               start_datetime: start,
               query_params: query,
               virtual_host: config.addressing == :virtual
             ) do
        {:ok, descriptor(:get, url, DateTime.add(start, seconds))}
      end
    end
  end

  @impl true
  def write_staging(key, chunks, cap, budget) do
    Operation.run(budget, fn directory, deadline ->
      with {:ok, config} <- Config.fetch() do
        path = Path.join(directory, "content")
        {size, digest} = spool(chunks, path, cap, deadline)

        put_file(config, key, path, size, digest, [], deadline) |> staging_result()
      end
    end)
  end

  @impl true
  def verify_and_publish(staging, sealed, expected, budget) do
    Operation.run(budget, fn directory, deadline ->
      with {:ok, config} <- Config.fetch(),
           :ok <- valid_expected(expected),
           {:ok, version} <- staging_version(config, staging, expected, deadline),
           {:ok, _facts} <-
             verify_object(
               config,
               staging,
               [{"versionId", version}],
               expected,
               Path.join(directory, "content"),
               deadline,
               :staging
             ),
           :ok <- publish(config, sealed, Path.join(directory, "content"), expected, deadline),
           {:ok, facts} <- verify_object(config, sealed, [], expected, nil, deadline, :sealed) do
        {:ok, %{sealed_key: sealed, facts: facts}}
      end
    end)
  end

  @impl true
  def verify_sealed(key, expected, budget) do
    Operation.run(budget, fn _directory, deadline ->
      with {:ok, config} <- Config.fetch(),
           :ok <- valid_expected(expected) do
        verify_object(config, key, [], expected, nil, deadline, :sealed)
      end
    end)
  end

  defp staging_version(config, key, expected, deadline) do
    case request(config, :head, key, deadline) do
      {:ok, %{status: 200} = response} ->
        size = Integer.to_string(expected.byte_size)

        case {Req.Response.get_header(response, "content-length"),
              Req.Response.get_header(response, "x-amz-version-id")} do
          {[^size], [version]} when version not in ["", "null"] -> {:ok, version}
          {[^size], _invalid} -> {:error, :storage_version_required}
          _mismatch -> {:error, :content_mismatch}
        end

      {:ok, %{status: 404}} ->
        {:error, :staging_missing}

      {:error, _reason} = error ->
        error

      _failure ->
        {:error, :storage_request_failed}
    end
  end

  defp publish(config, key, path, expected, deadline) do
    metadata = [
      {"if-none-match", "*"},
      {"x-amz-meta-declared-media-type-sha256", media_digest(expected.media_type)}
    ]

    case put_file(config, key, path, expected.byte_size, expected.sha256, metadata, deadline) do
      {:ok, %{status: status}} when status in [200, 201, 204, 412] -> :ok
      {:ok, %{status: 409}} -> {:error, :storage_publication_conflict}
      {:error, _reason} = error -> error
      _failure -> {:error, :storage_write_failed}
    end
  end

  defp put_file(config, key, path, size, digest, extra_headers, deadline) do
    headers =
      @delivery_headers ++
        extra_headers ++
        [
          {"content-length", Integer.to_string(size)},
          {"x-amz-checksum-sha256", Base.encode64(digest)}
        ]

    request(config, :put, key, deadline, body: File.stream!(path, 64 * 1024), headers: headers)
  end

  defp verify_object(config, key, query, expected, path, deadline, kind) do
    with_file(path, fn file ->
      into = fn data, context -> verify_chunk(data, context, expected, file, deadline, kind) end

      case request(config, :get, key, deadline, query: query, into: into) do
        {:ok, %{status: 200} = response} -> verify_response(response, expected, kind)
        {:error, _reason} = error -> error
        _failure -> {:error, :storage_request_failed}
      end
    end)
  end

  defp verify_chunk(
         {:data, bytes},
         {request, %{status: 200} = response},
         expected,
         file,
         deadline,
         kind
       ) do
    Operation.remaining(deadline)
    {size, hash} = Map.get(response.private, :content, {0, :crypto.hash_init(:sha256)})
    size = size + byte_size(bytes)
    if size > expected.byte_size, do: throw({:storage_error, mismatch(kind)})
    if file, do: :ok = IO.binwrite(file, bytes)
    content = {size, :crypto.hash_update(hash, bytes)}
    {:cont, {request, Req.Response.put_private(response, :content, content)}}
  end

  defp verify_chunk(data, context, _expected, _file, deadline, _kind) do
    Operation.remaining(deadline)
    HTTPClient.collect_control(data, context)
  end

  defp verify_response(response, expected, kind) do
    {size, hash} = Map.get(response.private, :content, {0, :crypto.hash_init(:sha256)})

    if size == expected.byte_size and :crypto.hash_final(hash) == expected.sha256 and
         metadata_matches?(response, expected, kind) do
      {:ok, expected}
    else
      {:error, mismatch(kind)}
    end
  end

  defp metadata_matches?(_response, _expected, :staging), do: true

  defp metadata_matches?(response, expected, :sealed) do
    Enum.all?(@delivery_headers, fn {name, value} ->
      Req.Response.get_header(response, name) == [value]
    end) and
      Req.Response.get_header(response, "x-amz-meta-declared-media-type-sha256") ==
        [media_digest(expected.media_type)]
  end

  defp request(config, method, key, deadline, opts \\ []) do
    timeout = Operation.remaining(deadline)
    {query, opts} = Keyword.pop(opts, :query, [])

    with {:ok, url} <-
           ExAws.S3.presigned_url(config.sdk, method, config.bucket, key,
             # SDK signing timestamps have whole-second precision. Keep backend
             # authentication valid for the budget; the monotonic caller deadline
             # still bounds work and does not promise remote cancellation.
             expires_in: div(timeout + 999, 1000) + 1,
             query_params: query,
             headers: Keyword.get(opts, :headers, []),
             virtual_host: config.addressing == :virtual
           ),
         {:ok, response} <-
           HTTPClient.request(
             [
               method: method,
               url: url,
               tls_options: config.tls_options,
               timeout: timeout
             ] ++ opts
           ) do
      Operation.remaining(deadline)
      {:ok, response}
    else
      {:error, %{reason: reason}} -> {:error, reason}
      {:error, _reason} -> {:error, :storage_request_failed}
    end
  end

  defp spool(chunks, path, cap, deadline) do
    with_file(path, fn file ->
      {size, state} =
        Enum.reduce(
          chunks,
          {0, :crypto.hash_init(:sha256)},
          &spool_chunk(&1, &2, file, cap, deadline)
        )

      {size, :crypto.hash_final(state)}
    end)
  end

  defp spool_chunk(bytes, {size, state}, file, cap, deadline) when is_binary(bytes) do
    Operation.remaining(deadline)
    size = size + byte_size(bytes)
    if size > cap, do: throw({:storage_error, :byte_cap_exceeded})
    :ok = IO.binwrite(file, bytes)
    {size, :crypto.hash_update(state, bytes)}
  end

  defp spool_chunk(_bytes, _state, _file, _cap, _deadline),
    do: throw({:storage_error, :invalid_staging_write})

  defp staging_result({:ok, %{status: status}}) when status in 200..299, do: :ok
  defp staging_result({:error, _reason} = error), do: error
  defp staging_result(_failure), do: {:error, :storage_write_failed}

  defp with_file(nil, fun), do: fun.(nil)

  defp with_file(path, fun) do
    File.open!(path, [:write, :binary, :raw, :exclusive], fun)
  end

  defp valid_expected(%{sha256: hash, byte_size: size, media_type: type})
       when is_binary(hash) and byte_size(hash) == 32 and is_integer(size) and size > 0 and
              is_binary(type) do
    max_bytes = Application.fetch_env!(:quick_train, :assets) |> Keyword.fetch!(:max_bytes)
    if size <= max_bytes, do: :ok, else: {:error, :content_mismatch}
  end

  defp valid_expected(_expected), do: {:error, :content_mismatch}

  defp lifetime(%DateTime{} = expires_at) do
    seconds = DateTime.diff(expires_at, DateTime.utc_now(), :second) - 1

    if seconds > 0,
      do: {:ok, seconds},
      else: {:error, :storage_access_expired}
  end

  defp descriptor(method, url, expiry) do
    %{
      method: method,
      uri: URI.parse(url),
      headers: [],
      expires_at: expiry,
      cache_control: "no-store",
      referrer_policy: "no-referrer"
    }
  end

  defp media_digest(type), do: :crypto.hash(:sha256, type) |> Base.encode16(case: :lower)
  defp mismatch(:staging), do: :content_mismatch
  defp mismatch(:sealed), do: :canonical_conflict
end
