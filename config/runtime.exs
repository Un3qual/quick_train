import Config

if System.get_env("PHX_SERVER") in ~w(true 1) do
  config :quick_train, QuickTrainWeb.Endpoint, server: true
end

config :quick_train, QuickTrainWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

config :quick_train, :local_development_authentication,
  enabled:
    config_env() == :dev and
      System.get_env("LOCAL_DEV_AUTH_ENABLED") in ~w(true 1)

config :quick_train, :human_oidc,
  issuer: System.get_env("OIDC_ISSUER"),
  client_id: System.get_env("OIDC_CLIENT_ID"),
  client_secret: System.get_env("OIDC_CLIENT_SECRET"),
  account_linking_policy: System.get_env("OIDC_ACCOUNT_LINKING_POLICY"),
  session_ttl_seconds: System.get_env("HUMAN_SESSION_TTL_SECONDS")

config :quick_train, :workos_enterprise,
  api_base_url: System.get_env("WORKOS_API_BASE_URL", "https://api.workos.com"),
  client_id: System.get_env("WORKOS_CLIENT_ID"),
  api_key_reference: System.get_env("WORKOS_API_KEY_REFERENCE"),
  webhook_secret_reference: System.get_env("WORKOS_WEBHOOK_SECRET_REFERENCE")

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
