defmodule QuickTrain.Authentication.OidcBeginResult do
  @moduledoc "The one-time public result of beginning an OIDC login."

  use Ash.Resource,
    otp_app: :quick_train,
    data_layer: :embedded,
    extensions: [AshGraphql.Resource]

  attributes do
    attribute :authorization_uri, :string do
      allow_nil? false
      public? true
      sensitive? true
    end

    attribute :state, :string do
      allow_nil? false
      public? true
      sensitive? true
    end

    attribute :client_proof, :string do
      allow_nil? false
      public? true
      sensitive? true
    end

    attribute :expires_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end
  end

  graphql do
    type :oidc_begin_result
  end
end
