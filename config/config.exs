import Config

config :ash, default_string_length_count: :codepoints

# INSERT ON CONFLICT handles simultaneous inserts; PostgreSQL MERGE can raise a uniqueness error.
config :ash_postgres, upsert_with_merge?: false

config :quick_train, Oban,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.Postgres,
  queues: [default: 10, assets: 5, dataset_imports: 5],
  lifeline: [rescue_after: {2, :hours}],
  pruner: [max_age: {1, :day}],
  repo: QuickTrain.Repo

config :quick_train, :authentication,
  enforce_https?: false,
  trusted_proxy_ips: [],
  oidc_callbacks: [],
  oidc_begin_window_ms: 60_000,
  oidc_begin_global_limit: 300,
  oidc_begin_network_limit: 20,
  oidc_outstanding_limit: 10_000,
  oidc_transaction_ttl_seconds: 300,
  session_max_lifetime_seconds: 8 * 60 * 60

config :quick_train, :assets,
  max_bytes: 25 * 1024 * 1024,
  staging_lifetime_seconds: 60 * 60,
  upload_access_lifetime_seconds: 15 * 60,
  read_access_lifetime_seconds: 5 * 60,
  operation_claim_seconds: 2 * 60,
  publication_deadline_ms: 30_000

config :quick_train, :dataset_imports,
  open_lifetime_seconds: 60 * 60,
  max_rows_per_import: 10_000,
  max_fields_per_row: 100,
  max_scalar_bytes_per_row: 256 * 1024,
  max_text_bytes: 64 * 1024,
  max_request_bytes: 512 * 1024

config :quick_train,
  ash_domains: [
    QuickTrain.Forms,
    QuickTrain.Datasets,
    QuickTrain.Assets,
    QuickTrain.Authentication,
    QuickTrain.Accounts,
    QuickTrain.Authorization,
    QuickTrain.EnterpriseIdentity,
    QuickTrain.Organizations
  ],
  ecto_repos: [QuickTrain.Repo],
  generators: [timestamp_type: :utc_datetime_usec]

config :quick_train, QuickTrainWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [json: QuickTrainWeb.ErrorJSON], layout: false],
  pubsub_server: QuickTrain.PubSub,
  live_view: [signing_salt: "quicktrain"]

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :authentication_operation, :authentication_failure]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
