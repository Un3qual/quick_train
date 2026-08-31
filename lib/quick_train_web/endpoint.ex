defmodule QuickTrainWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :quick_train

  @session_options [
    store: :cookie,
    key: "_quick_train_key",
    signing_salt: "quicktrain-session",
    same_site: "Lax",
    secure: true,
    http_only: true
  ]

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]
  plug QuickTrainWeb.Authentication.RequestSecurity
  plug QuickTrainWeb.Authentication.BearerAuthentication

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    length:
      Application.compile_env!(:quick_train, :dataset_imports)
      |> Keyword.fetch!(:max_request_bytes),
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug QuickTrainWeb.Router
end
