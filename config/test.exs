import Config

config :quick_train, QuickTrain.Repo,
  username: System.get_env("QUICK_TRAIN_TEST_DATABASE_USERNAME", "quick_train"),
  password: System.get_env("QUICK_TRAIN_TEST_DATABASE_PASSWORD", "quick_train"),
  hostname: System.get_env("QUICK_TRAIN_TEST_DATABASE_HOST", "localhost"),
  port: String.to_integer(System.get_env("QUICK_TRAIN_POSTGRES_PORT", "55433")),
  database:
    System.get_env("QUICK_TRAIN_TEST_DATABASE_NAME", "quick_train_test") <>
      System.get_env("MIX_TEST_PARTITION", ""),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2,
  log: false

config :ash, :disable_async?, true

config :quick_train, QuickTrainWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "pM86mIBn3Bgbc4DH0ixmGqZz1YqN/1PYnNFbh5+hurSMBaA94okFGYiIOvLJhoMW",
  server: false

config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime
config :phoenix, sort_verified_routes_query_params: true
