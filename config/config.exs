import Config

config :quick_train,
  ash_domains: [
    QuickTrain.Accounts.Domain,
    QuickTrain.Audit.Domain,
    QuickTrain.Authorization.Domain,
    QuickTrain.DurableDelivery.Domain,
    QuickTrain.EnterpriseIdentity.Domain,
    QuickTrain.Integrations.Domain,
    QuickTrain.Operations.Domain,
    QuickTrain.Organizations.Domain
  ],
  ecto_repos: [QuickTrain.Repo],
  generators: [timestamp_type: :utc_datetime_usec]

config :quick_train, Oban,
  repo: QuickTrain.Repo,
  queues: [default: 10, integrations: 5],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 30 * 24 * 60 * 60},
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(60)}
  ]

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
