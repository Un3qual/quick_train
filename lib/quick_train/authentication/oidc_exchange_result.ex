defmodule QuickTrain.Authentication.OidcExchangeResult do
  @moduledoc "The one-time public result of exchanging an OIDC login."

  use Ash.Resource,
    otp_app: :quick_train,
    data_layer: :embedded,
    extensions: [AshGraphql.Resource]

  attributes do
    attribute :token, :string do
      allow_nil? false
      public? true
      sensitive? true
    end

    attribute :session_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :expires_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    attribute :user, :struct do
      public? false
      constraints instance_of: QuickTrain.Accounts.User
    end
  end

  graphql do
    type :oidc_exchange_result
  end
end
