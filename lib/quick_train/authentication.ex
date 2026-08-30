defmodule QuickTrain.Authentication do
  @moduledoc "Public authentication behavior and typed API results."

  use Ash.Domain, otp_app: :quick_train, extensions: [AshGraphql.Domain]

  alias QuickTrain.Authentication.Api

  graphql do
    authorize? false

    queries do
      action Api, :api_version, :api_version
    end

    mutations do
      action Api, :begin_oidc_login, :begin_oidc_login, args: [:callback_key]

      action Api, :exchange_oidc_login, :exchange_oidc_login, args: [:code, :state, :client_proof]
    end
  end

  resources do
    resource Api do
      define :api_version, action: :api_version
      define :begin_oidc_login, action: :begin_oidc_login, args: [:callback_key]

      define :exchange_oidc_login,
        action: :exchange_oidc_login,
        args: [:code, :state, :client_proof]
    end
  end
end
