defmodule QuickTrain.LocalStorageSetup do
  import SweetXml, only: [sigil_x: 2]

  def run do
    endpoint = URI.parse(System.fetch_env!("QUICK_TRAIN_STORAGE_ENDPOINT"))

    unless endpoint.scheme == "https" and endpoint.host == "127.0.0.1" and
             endpoint.port in 1..65_535 and endpoint.path in [nil, ""] and
             is_nil(endpoint.userinfo) and is_nil(endpoint.query) and is_nil(endpoint.fragment) do
      Mix.raise("Local bootstrap requires a direct https://127.0.0.1:<port> endpoint.")
    end

    bucket = System.fetch_env!("QUICK_TRAIN_STORAGE_BUCKET")
    region = System.fetch_env!("QUICK_TRAIN_STORAGE_REGION")
    origins = origins!()

    config = %{
      scheme: "https://",
      host: endpoint.host,
      port: endpoint.port,
      region: region,
      access_key_id: System.fetch_env!("QUICK_TRAIN_STORAGE_ACCESS_KEY"),
      secret_access_key: System.fetch_env!("QUICK_TRAIN_STORAGE_SECRET_KEY"),
      virtual_host: false,
      normalize_path: false,
      http_client: QuickTrain.Assets.Storage.S3.HTTPClient,
      json_codec: Jason,
      debug_requests: false,
      retries: [max_attempts: 1],
      http_opts: [
        timeout: 5_000,
        tls_options: [
          verify: :verify_peer,
          cacertfile: System.fetch_env!("QUICK_TRAIN_STORAGE_CA_FILE")
        ]
      ]
    }

    {:ok, _} = Application.ensure_all_started(:req)
    {:ok, _} = Application.ensure_all_started(:ex_aws)

    case request(ExAws.S3.head_bucket(bucket), config) do
      {:ok, _} -> :ok
      {:error, {:http_error, 404, _}} -> request!(ExAws.S3.put_bucket(bucket, region), config)
      _ -> Mix.raise("Cannot inspect the local storage bucket; check its TLS and credentials.")
    end

    versioning = "<VersioningConfiguration><Status>Enabled</Status></VersioningConfiguration>"
    request!(ExAws.S3.put_bucket_versioning(bucket, versioning), config)
    response = request!(ExAws.S3.get_bucket_versioning(bucket), config)

    unless SweetXml.xpath(response.body, ~x"/VersioningConfiguration/Status/text()"s) == "Enabled" do
      Mix.raise("Local storage must confirm bucket versioning is Enabled.")
    end

    request!(
      ExAws.S3.put_bucket_cors(bucket, [
        %{
          allowed_origins: origins,
          allowed_methods: ["GET", "HEAD", "POST"],
          allowed_headers: ["content-type"],
          exposed_headers: ["content-disposition", "content-type", "cache-control"],
          max_age_seconds: 300
        }
      ]),
      config
    )

    cors = request!(ExAws.S3.get_bucket_cors(bucket), config)

    unless Enum.sort(
             SweetXml.xpath(cors.body, ~x"/CORSConfiguration/CORSRule/AllowedOrigin/text()"ls)
           ) ==
             Enum.sort(origins) and
             Enum.sort(
               SweetXml.xpath(cors.body, ~x"/CORSConfiguration/CORSRule/AllowedMethod/text()"ls)
             ) ==
               ["GET", "HEAD", "POST"] do
      Mix.raise("Local storage must confirm the configured browser CORS origins and methods.")
    end

    Mix.shell().info(
      "Local storage ready at #{URI.to_string(endpoint)}/#{bucket} (versioning enabled)."
    )
  end

  defp origins! do
    origins = System.fetch_env!("QUICK_TRAIN_STORAGE_CORS_ORIGINS_JSON") |> Jason.decode!()

    unless is_list(origins) and origins != [] and
             Enum.all?(origins, fn
               origin when is_binary(origin) ->
                 uri = URI.parse(origin)

                 uri.scheme in ["http", "https"] and uri.host == "localhost" and
                   uri.port in 1..65_535 and uri.path in [nil, ""] and
                   is_nil(uri.userinfo) and is_nil(uri.query) and is_nil(uri.fragment)

               _ ->
                 false
             end) do
      Mix.raise("Local CORS origins must be explicit http(s)://localhost:<port> origins.")
    end

    origins
  end

  defp request!(operation, config) do
    case request(operation, config) do
      {:ok, response} ->
        response

      _ ->
        Mix.raise(
          "Local storage bootstrap failed; check its TLS, credentials and bucket controls."
        )
    end
  end

  defp request(operation, config) do
    ExAws.Operation.perform(operation, config)
  rescue
    _ -> {:error, :storage_request_failed}
  end
end

QuickTrain.LocalStorageSetup.run()
