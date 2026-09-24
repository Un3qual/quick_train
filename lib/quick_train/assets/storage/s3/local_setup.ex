defmodule QuickTrain.Assets.Storage.S3.LocalSetup do
  @moduledoc false

  import SweetXml, only: [sigil_x: 2]

  alias ExAws.S3, as: SDK

  def run(storage, origins) do
    cond do
      not local_storage?(storage) -> {:error, :local_storage_required}
      not valid_origins?(origins) -> {:error, :invalid_local_cors_origins}
      true -> bootstrap(storage, origins)
    end
  end

  defp local_storage?(%{profile: :local, addressing: :path, endpoint: endpoint}) do
    endpoint.scheme == "https" and endpoint.host == "127.0.0.1" and
      endpoint.port in 1..65_535 and endpoint.path in [nil, "", "/"] and
      is_nil(endpoint.userinfo) and is_nil(endpoint.query) and is_nil(endpoint.fragment)
  end

  defp local_storage?(_storage), do: false

  defp valid_origins?(origins) when is_list(origins) and origins != [] do
    Enum.all?(origins, fn
      origin when is_binary(origin) ->
        uri = URI.parse(origin)

        uri.scheme in ["http", "https"] and uri.host == "localhost" and
          uri.port in 1..65_535 and uri.path in [nil, ""] and
          is_nil(uri.userinfo) and is_nil(uri.query) and is_nil(uri.fragment)

      _invalid ->
        false
    end)
  end

  defp valid_origins?(_origins), do: false

  defp bootstrap(storage, origins) do
    versioning = "<VersioningConfiguration><Status>Enabled</Status></VersioningConfiguration>"

    cors = [
      %{
        allowed_origins: origins,
        allowed_methods: ["GET", "HEAD", "POST"],
        allowed_headers: ["content-type"],
        exposed_headers: ["content-disposition", "content-type", "cache-control"],
        max_age_seconds: 300
      }
    ]

    with {:ok, _response} <- ensure_bucket(storage),
         {:ok, _response} <-
           request(SDK.put_bucket_versioning(storage.bucket, versioning), storage),
         {:ok, versioning} <- request(SDK.get_bucket_versioning(storage.bucket), storage),
         document <- SweetXml.parse(versioning.body, dtd: :none, quiet: true),
         "Enabled" <- SweetXml.xpath(document, ~x"/VersioningConfiguration/Status/text()"s),
         {:ok, _response} <- request(SDK.put_bucket_cors(storage.bucket, cors), storage),
         {:ok, cors} <- request(SDK.get_bucket_cors(storage.bucket), storage),
         document <- SweetXml.parse(cors.body, dtd: :none, quiet: true),
         true <-
           Enum.sort(
             SweetXml.xpath(document, ~x"/CORSConfiguration/CORSRule/AllowedOrigin/text()"ls)
           ) ==
             Enum.sort(origins),
         ["GET", "HEAD", "POST"] <-
           Enum.sort(
             SweetXml.xpath(document, ~x"/CORSConfiguration/CORSRule/AllowedMethod/text()"ls)
           ) do
      :ok
    else
      _failure -> {:error, :local_storage_bootstrap_failed}
    end
  rescue
    # reach:disable-next-line bare_rescue -- Never expose credentials or provider response content.
    _exception -> {:error, :local_storage_bootstrap_failed}
  catch
    :exit, _reason -> {:error, :local_storage_bootstrap_failed}
  end

  defp ensure_bucket(storage) do
    case request(SDK.head_bucket(storage.bucket), storage) do
      {:error, {:http_error, 404, _response}} ->
        request(SDK.put_bucket(storage.bucket, storage.sdk.region), storage)

      result ->
        result
    end
  end

  defp request(operation, storage), do: ExAws.Operation.perform(operation, storage.sdk)
end
