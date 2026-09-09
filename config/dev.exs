import Config

config :quick_train, QuickTrain.Repo,
  username: System.get_env("QUICK_TRAIN_DATABASE_USERNAME", "quick_train"),
  password: System.get_env("QUICK_TRAIN_DATABASE_PASSWORD", "quick_train"),
  hostname: System.get_env("QUICK_TRAIN_DATABASE_HOST", "localhost"),
  port: String.to_integer(System.get_env("QUICK_TRAIN_POSTGRES_PORT", "55433")),
  database: System.get_env("QUICK_TRAIN_DATABASE_NAME", "quick_train_dev"),
  show_sensitive_data_on_connection_error: true,
  stacktrace: true,
  pool_size: 10

config :quick_train, QuickTrainWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4005],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "6gdLoRudb/eun+m28QtxgRPxkKO7rAmQW7r+klAbPoZ3QqoD5ocBxziXwoRwRoMO",
  watchers: []

config :logger, :default_formatter, format: "[$level] $message\n"
config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
