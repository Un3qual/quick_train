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
    read :read do
      primary? true
      public? false
    end

    read :authenticate_bearer do
      public? false
      argument :token_hash, :binary, allow_nil?: false, sensitive?: true
      get? true

      filter expr(
               token_hash == ^arg(:token_hash) and is_nil(revoked_at) and expires_at > now() and
                 exists(user, status == "active")
             )

      prepare build(load: [:user])
    end

    action :issue_bearer, :map do
      public? false
      argument :user_id, :uuid, allow_nil?: false
      argument :lifetime_seconds, :integer

      run QuickTrain.Accounts.Session.Actions.IssueBearer
    end

    action :cleanup_retained, :boolean do
      public? false
      argument :now, :utc_datetime_usec, allow_nil?: false
      run QuickTrain.Accounts.Session.Actions.CleanupRetained
    end

    create :persist do
      public? false
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
      validate QuickTrain.Accounts.Session.Validations.LifetimeWithinMaximum
    end

    update :revoke do
      public? false
      accept []
      change atomic_update(:revoked_at, expr(now()))
    end

    destroy :delete_retained do
      public? false
    end
  end

  identities do
    identity :token_hash, [:token_hash]
  end
end
