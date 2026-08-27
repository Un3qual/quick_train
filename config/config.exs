import Config

config :quick_train,
  ash_domains: [
    QuickTrain.Accounts,
    QuickTrain.Authorization.Domain,
    QuickTrain.EnterpriseIdentity.Domain,
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
