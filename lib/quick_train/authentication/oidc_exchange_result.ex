defmodule QuickTrain.Authentication.OidcExchangeResult do
  @moduledoc "The one-time public result of exchanging an OIDC login."

  alias QuickTrain.Accounts.User

  use Ash.Resource,
    otp_app: :quick_train,
    data_layer: :embedded,
    extensions: [AshGraphql.Resource]

  attributes do
    attribute :token, :string,
      allow_nil?: false,
      public?: true,
      sensitive?: true

    attribute :session_id, :uuid,
      allow_nil?: false,
      public?: true

    attribute :expires_at, :utc_datetime_usec,
      allow_nil?: false,
      public?: true

    attribute :user, :struct, constraints: [instance_of: User]
  end

  graphql do
    type :oidc_exchange_result
  end
end
