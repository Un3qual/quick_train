defmodule QuickTrain.Authentication.OidcBeginResult do
  @moduledoc "The one-time public result of beginning an OIDC login."

  use Ash.Resource,
    otp_app: :quick_train,
    data_layer: :embedded,
    extensions: [AshGraphql.Resource]

  attributes do
    attribute :authorization_uri, :string,
      allow_nil?: false,
      public?: true,
      sensitive?: true

    attribute :state, :string,
      allow_nil?: false,
      public?: true,
      sensitive?: true

    attribute :client_proof, :string,
      allow_nil?: false,
      public?: true,
      sensitive?: true

    attribute :expires_at, :utc_datetime_usec,
      allow_nil?: false,
      public?: true
  end

  graphql do
    type :oidc_begin_result
  end
end
