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
  case System.get_env("OIDC_CALLBACKS_JSON") do
    nil ->
      []

    callbacks_json ->
      callbacks_json
      |> Jason.decode!()
      |> Enum.map(fn {key, uri} -> {key, uri} end)
  end

trusted_proxy_ips =
  System.get_env("TRUSTED_PROXY_IPS", "")
  |> String.split(",", trim: true)
  |> Enum.map(&String.trim/1)

parse_positive_integer = fn name, default ->
  case System.get_env(name) do
    nil ->
      default

    value ->
      case Integer.parse(value) do
        {integer, ""} when integer > 0 -> integer
        _invalid -> raise "#{name} must be a positive integer"
      end
  end
end

config :quick_train, :authentication,
  oidc_callbacks: oidc_callbacks,
  trusted_proxy_ips: trusted_proxy_ips,
  oidc_begin_window_ms: parse_positive_integer.("OIDC_BEGIN_WINDOW_MS", 60_000),
  oidc_begin_global_limit: parse_positive_integer.("OIDC_BEGIN_GLOBAL_LIMIT", 300),
  oidc_begin_network_limit: parse_positive_integer.("OIDC_BEGIN_NETWORK_LIMIT", 20),
  oidc_outstanding_limit: parse_positive_integer.("OIDC_OUTSTANDING_LIMIT", 10_000),
  oidc_transaction_ttl_seconds: parse_positive_integer.("OIDC_TRANSACTION_TTL_SECONDS", 300),
  oidc_replay_retention_seconds: parse_positive_integer.("OIDC_REPLAY_RETENTION_SECONDS", 86_400),
  session_max_lifetime_seconds:
    parse_positive_integer.("HUMAN_SESSION_MAX_LIFETIME_SECONDS", 8 * 60 * 60),
  session_retention_seconds: parse_positive_integer.("HUMAN_SESSION_RETENTION_SECONDS", 86_400)

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
