defmodule QuickTrain.Assets.Storage.S3.Config do
  @moduledoc false

  @invalid {:error, :invalid_storage_configuration}

  def fetch do
    case Application.fetch_env(:quick_train, :s3_storage) do
      {:ok, options} -> new(options)
      :error -> {:error, :storage_not_configured}
    end
  end

  def new(options) when is_list(options) do
    with true <- Keyword.keyword?(options),
         profile when profile in [:local, :aws] <- options[:profile],
         addressing when addressing in [:path, :virtual] <- options[:addressing],
         {:ok, endpoint} <- endpoint(options[:endpoint]),
         true <- valid_bucket?(options[:bucket]),
         true <- valid_region?(options[:region]),
         true <- valid_endpoint?(profile, endpoint, options[:region]),
         true <- nonempty_string?(options[:access_key_id]),
         true <- nonempty_string?(options[:secret_access_key]),
         true <- is_nil(options[:security_token]) or nonempty_string?(options[:security_token]),
         {:ok, application_hosts} <- host_list(options[:application_hosts], :host),
         true <- application_hosts != [],
         {:ok, cookie_domains} <- host_list(options[:cookie_domains], :cookie_domain),
         {:ok, host} <- storage_host(endpoint.host, options[:bucket], addressing),
         true <- isolated?(host, application_hosts, cookie_domains),
         {:ok, tls_options} <- tls_options(profile, options[:ca_file]) do
      {:ok,
       %{
         sdk: sdk_config(options, endpoint, tls_options),
         bucket: options[:bucket],
         host: host,
         endpoint: endpoint,
         tls_options: tls_options,
         profile: profile,
         addressing: addressing,
         application_hosts: application_hosts,
         cookie_domains: cookie_domains
       }}
    else
      _invalid -> @invalid
    end
  rescue
    _error -> @invalid
  end

  def new(_options), do: @invalid

  defp endpoint(value) when is_binary(value) do
    with {:ok, %URI{scheme: "https", userinfo: nil, query: nil, fragment: nil} = uri} <-
           URI.new(value),
         true <- uri.path in [nil, "/"],
         true <- is_integer(uri.port) and uri.port in 1..65_535,
         {:ok, host} <- normalize_host(uri.host) do
      {:ok, %{uri | host: host, authority: nil}}
    else
      _invalid -> @invalid
    end
  end

  defp endpoint(_value), do: @invalid

  defp valid_endpoint?(:local, _endpoint, _region), do: true

  defp valid_endpoint?(:aws, endpoint, region) do
    suffix = if String.starts_with?(region, "cn-"), do: "amazonaws.com.cn", else: "amazonaws.com"

    Regex.match?(~r/\A[a-z]{2}(?:-[a-z]+)+-[0-9]+\z/, region) and
      endpoint.host == "s3.#{region}.#{suffix}" and endpoint.port == 443
  end

  defp valid_bucket?(value) when is_binary(value) do
    byte_size(value) in 3..63 and
      Regex.match?(~r/\A[a-z0-9][a-z0-9.-]*[a-z0-9]\z/, value) and
      not String.contains?(value, ["..", ".-", "-."]) and not ip_address?(value)
  end

  defp valid_bucket?(_value), do: false

  defp valid_region?(value) when is_binary(value),
    do: byte_size(value) in 1..64 and Regex.match?(~r/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/, value)

  defp valid_region?(_value), do: false

  defp storage_host(host, _bucket, :path), do: {:ok, host}

  defp storage_host(host, bucket, :virtual) do
    if ip_address?(host), do: @invalid, else: normalize_host("#{bucket}.#{host}")
  end

  defp host_list(values, kind) when is_list(values) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, hosts} ->
      value =
        if kind == :cookie_domain and is_binary(value),
          do: String.replace_prefix(value, ".", ""),
          else: value

      case normalize_host(value) do
        {:ok, host} -> {:cont, {:ok, [host | hosts]}}
        _invalid -> {:halt, @invalid}
      end
    end)
    |> case do
      {:ok, hosts} -> {:ok, hosts |> Enum.reverse() |> Enum.uniq()}
      invalid -> invalid
    end
  end

  defp host_list(_values, _kind), do: @invalid

  defp normalize_host(value) when is_binary(value) do
    host = value |> String.downcase() |> String.replace_suffix(".", "")

    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, address} ->
        {:ok, address |> :inet.ntoa() |> List.to_string()}

      {:error, _reason} ->
        if byte_size(host) in 1..253 and
             Enum.all?(
               String.split(host, "."),
               &Regex.match?(~r/\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/, &1)
             ) do
          {:ok, host}
        else
          @invalid
        end
    end
  end

  defp normalize_host(_value), do: @invalid

  defp ip_address?(host),
    do: match?({:ok, _address}, :inet.parse_address(String.to_charlist(host)))

  defp isolated?(host, application_hosts, cookie_domains) do
    host not in application_hosts and
      not Enum.any?(cookie_domains, &(host == &1 or String.ends_with?(host, "." <> &1)))
  end

  defp tls_options(:aws, nil), do: {:ok, []}

  defp tls_options(_profile, ca_file) when is_binary(ca_file) do
    if File.regular?(ca_file) and File.open(ca_file, [:read], fn _file -> :ok end) == {:ok, :ok} do
      {:ok, [cacertfile: ca_file]}
    else
      @invalid
    end
  end

  defp tls_options(_profile, _ca_file), do: @invalid

  defp nonempty_string?(value) when is_binary(value),
    do: String.valid?(value) and String.trim(value) != ""

  defp nonempty_string?(_value), do: false

  defp sdk_config(options, endpoint, tls_options) do
    # ExAws.Config.new/2 merges ambient SDK configuration, including refreshable
    # credential providers. A complete map keeps this boundary entirely explicit.
    %{
      access_key_id: options[:access_key_id],
      secret_access_key: options[:secret_access_key],
      security_token: options[:security_token],
      region: options[:region],
      host: endpoint.host,
      port: endpoint.port,
      scheme: "https://",
      virtual_host: options[:addressing] == :virtual,
      bucket_as_host: false,
      http_client: QuickTrain.Assets.Storage.S3.HTTPClient,
      http_opts: [tls_options: tls_options],
      json_codec: Jason,
      retries: [max_attempts: 1, base_backoff_in_ms: 0, max_backoff_in_ms: 0],
      debug_requests: false,
      normalize_path: true
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end
end
