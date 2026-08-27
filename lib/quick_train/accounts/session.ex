defmodule QuickTrain.Accounts.Session do
  @moduledoc "An account-required session, optionally scoped to an organization."

  use Ash.Resource,
    domain: QuickTrain.Accounts,
    data_layer: AshPostgres.DataLayer

  alias QuickTrain.Accounts.User
  alias QuickTrain.Organizations.Organization

  postgres do
    table "sessions"
    repo QuickTrain.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :authentication_method, :string, allow_nil?: false, public?: true, default: "oidc"
    attribute :token_hash, :string, public?: true, sensitive?: true

    attribute :issued_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :expires_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :revoked_at, :utc_datetime_usec, public?: true
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :user, User,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :organization, Organization,
      allow_nil?: true,
      attribute_public?: true
  end

  actions do
    defaults [:read]

    create :issue do
      accept [
        :user_id,
        :organization_id,
        :authentication_method,
        :token_hash
      ]

      change atomic_set(:issued_at, expr(now()))
      change atomic_set(:expires_at, expr(datetime_add(now(), 8, :hour)))
      validate QuickTrain.Accounts.Session.Validations.ActiveUser
      validate QuickTrain.Accounts.Session.Validations.ActiveOrganizationMembership
    end

    update :revoke do
      accept [:revoked_at]
    end
  end
end
