defmodule QuickTrain.Authentication.Api do
  @moduledoc "The public, behavior-only authentication API."

  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Authentication,
    extensions: [AshGraphql.Resource]

  graphql do
    generate_object? false
  end

  actions do
    action :api_version, :string do
      allow_nil? false

      run fn _input, _context ->
        {:ok, :quick_train |> Application.spec(:vsn) |> to_string()}
      end
    end

    action :begin_oidc_login, QuickTrain.Authentication.OidcBeginResult do
      allow_nil? false

      argument :callback_key, :string, allow_nil?: false

      run QuickTrain.Authentication.Api.Actions.BeginOidcLogin
    end

    action :exchange_oidc_login, QuickTrain.Authentication.OidcExchangeResult do
      allow_nil? false

      argument :code, :string, allow_nil?: false, sensitive?: true
      argument :state, :string, allow_nil?: false, sensitive?: true
      argument :client_proof, :string, allow_nil?: false, sensitive?: true

      run QuickTrain.Authentication.Api.Actions.ExchangeOidcLogin
    end
  end
end
