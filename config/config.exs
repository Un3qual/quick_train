import Config

config :quick_train, Oban,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.Postgres,
  queues: [default: 10],
  lifeline: [rescue_after: {2, :hours}],
  pruner: [max_age: {1, :day}],
  repo: QuickTrain.Repo

config :quick_train, :authentication, session_max_lifetime_seconds: 8 * 60 * 60

config :quick_train,
  ash_domains: [
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
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
