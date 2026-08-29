defmodule QuickTrain.Accounts.Session do
  @moduledoc "A hash-only bearer credential for one active global user account."

  use Ash.Resource,
    domain: QuickTrain.Accounts,
    data_layer: AshPostgres.DataLayer

  alias QuickTrain.Accounts.User

  postgres do
    table "sessions"
    repo QuickTrain.Repo
    identity_index_names token_hash: "sessions_token_hash_index"

    custom_indexes do
      index [:expires_at], name: "sessions_expires_at_index"
      index [:revoked_at], name: "sessions_revoked_at_index", where: "revoked_at IS NOT NULL"
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :authentication_method, :string, allow_nil?: false, default: "oidc"
    attribute :token_hash, :binary, allow_nil?: false, sensitive?: true

    attribute :issued_at, :utc_datetime_usec, allow_nil?: false
    attribute :expires_at, :utc_datetime_usec, allow_nil?: false
    attribute :revoked_at, :utc_datetime_usec
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, User do
      allow_nil? false
      filter expr(status == "active")
    end
  end

  actions do
    defaults [:read]

    action :issue_bearer, :map do
      argument :user_id, :uuid, allow_nil?: false
      argument :lifetime_seconds, :integer

      run QuickTrain.Accounts.Session.Actions.IssueBearer
    end

    action :cleanup_retained, :integer do
      argument :now, :utc_datetime_usec, allow_nil?: false
      run QuickTrain.Accounts.Session.Actions.CleanupRetained
    end

    create :persist do
      argument :user_id, :uuid, allow_nil?: false

      accept [
        :authentication_method,
        :token_hash,
        :issued_at,
        :expires_at
      ]

      change manage_relationship(:user_id, :user,
               type: :append,
               value_is_key: :id,
               authorize?: false,
               error_path: :user_id
             )

      validate compare(:expires_at, greater_than: :issued_at)
    end

    update :revoke do
      accept []
      change set_attribute(:revoked_at, expr(now()))
    end

    destroy :delete_retained
  end

  identities do
    identity :token_hash, [:token_hash]
  end
end
