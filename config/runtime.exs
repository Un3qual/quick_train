import Config

if System.get_env("PHX_SERVER") in ~w(true 1) do
  config :quick_train, QuickTrainWeb.Endpoint, server: true
end

config :quick_train, QuickTrainWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

config :quick_train, :human_oidc,
  issuer: System.get_env("OIDC_ISSUER"),
  client_id: System.get_env("OIDC_CLIENT_ID"),
  client_secret: System.get_env("OIDC_CLIENT_SECRET")

oidc_callbacks =
  case System.fetch_env("OIDC_CALLBACKS_JSON") do
    :error ->
      nil

    {:ok, callbacks_json} ->
      callbacks_json
      |> Jason.decode!()
      |> Enum.map(fn {key, uri} -> {key, uri} end)
  end

trusted_proxy_ips =
  case System.fetch_env("TRUSTED_PROXY_IPS") do
    :error -> nil
    {:ok, addresses} -> addresses |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
  end

parse_positive_integer = fn name ->
  case System.fetch_env(name) do
    :error ->
      nil

    {:ok, value} ->
      case Integer.parse(value) do
        {integer, ""} when integer > 0 -> integer
        _invalid -> raise "#{name} must be a positive integer"
      end
  end
end

authentication_overrides =
  [
    oidc_callbacks: oidc_callbacks,
    trusted_proxy_ips: trusted_proxy_ips,
    oidc_begin_window_ms: parse_positive_integer.("OIDC_BEGIN_WINDOW_MS"),
    oidc_begin_global_limit: parse_positive_integer.("OIDC_BEGIN_GLOBAL_LIMIT"),
    oidc_begin_network_limit: parse_positive_integer.("OIDC_BEGIN_NETWORK_LIMIT"),
    oidc_outstanding_limit: parse_positive_integer.("OIDC_OUTSTANDING_LIMIT"),
    oidc_transaction_ttl_seconds: parse_positive_integer.("OIDC_TRANSACTION_TTL_SECONDS"),
    session_max_lifetime_seconds: parse_positive_integer.("HUMAN_SESSION_MAX_LIFETIME_SECONDS")
  ]
  |> Enum.reject(fn {_key, value} -> is_nil(value) end)

if authentication_overrides != [] do
  config :quick_train, :authentication, authentication_overrides
end

# The separate storage integration runner supplies its configuration explicitly.
# Ordinary tests always retain the in-memory adapter from config/test.exs.
if config_env() != :test do
  storage_env = fn name -> System.get_env("QUICK_TRAIN_STORAGE_" <> name) end

  parse_storage_json = fn value ->
    case value do
      nil ->
        nil

      value ->
        case Jason.decode(value) do
          {:ok, decoded} -> decoded
          {:error, _reason} -> raise "invalid storage configuration"
        end
    end
  end

  storage_options = [
    profile: storage_env.("PROFILE"),
    endpoint: storage_env.("ENDPOINT"),
    region: storage_env.("REGION"),
    bucket: storage_env.("BUCKET"),
    access_key_id: storage_env.("ACCESS_KEY"),
    secret_access_key: storage_env.("SECRET_KEY"),
    security_token: storage_env.("SESSION_TOKEN"),
    addressing: storage_env.("ADDRESSING"),
    ca_file: storage_env.("CA_FILE"),
    application_hosts: storage_env.("APPLICATION_HOSTS_JSON"),
    cookie_domains: storage_env.("COOKIE_DOMAINS_JSON")
  ]

  if Enum.any?(storage_options, fn {_key, value} -> not is_nil(value) end) do
    storage_options =
      storage_options
      |> Keyword.update!(:profile, fn
        "local" -> :local
        "aws" -> :aws
        _invalid -> nil
      end)
      |> Keyword.update!(:addressing, fn
        "path" -> :path
        "virtual" -> :virtual
        _invalid -> nil
      end)
      |> Keyword.update!(:application_hosts, parse_storage_json)
      |> Keyword.update!(:cookie_domains, parse_storage_json)

    case QuickTrain.Assets.Storage.S3.Config.new(storage_options) do
      {:ok, _validated} ->
        config :quick_train, :s3_storage, storage_options
        config :quick_train, :assets, storage_adapter: QuickTrain.Assets.Storage.S3

      {:error, _reason} ->
        raise "invalid storage configuration"
    end
  end
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise "DATABASE_URL is required in production"

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "SECRET_KEY_BASE is required in production"

  host = System.get_env("PHX_HOST", "example.com")
  database_ssl? = System.get_env("DATABASE_SSL", "true") not in ~w(false 0)
  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :quick_train, QuickTrain.Repo,
    ssl: database_ssl?,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE", "10")),
    socket_options: maybe_ipv6

  config :quick_train, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :quick_train, QuickTrainWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}],
    secret_key_base: secret_key_base
end
