defmodule QuickTrain.Accounts.Session do
  @moduledoc "An account-required session, optionally scoped to an organization."

  use Ash.Resource,
    domain: QuickTrain.Accounts.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "sessions"
    repo QuickTrain.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :organization_id, :uuid, public?: true
    attribute :authentication_method, :string, allow_nil?: false, public?: true, default: "oidc"
    attribute :token_hash, :string, public?: true, sensitive?: true
    attribute :issued_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :expires_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :revoked_at, :utc_datetime_usec, public?: true
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :user, QuickTrain.Accounts.User do
      allow_nil? false
      attribute_public? true
    end
  end

  actions do
    defaults [:read]

    create :issue do
      accept [
        :user_id,
        :organization_id,
        :authentication_method,
        :token_hash,
        :issued_at,
        :expires_at
      ]
    end

    update :revoke do
      accept [:revoked_at]
    end
  end
end
