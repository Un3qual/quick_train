defmodule QuickTrain.Accounts.OidcLoginTransaction do
  @moduledoc "Short-lived server-side OIDC state and PKCE material."

  use Ash.Resource,
    domain: QuickTrain.Accounts,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "oidc_login_transactions"
    repo QuickTrain.Repo
    identity_index_names state_hash: "oidc_login_transactions_state_hash_index"
  end

  attributes do
    uuid_primary_key :id
    attribute :state_hash, :string, allow_nil?: false, public?: true, sensitive?: true
    attribute :code_verifier, :string, allow_nil?: false, public?: true, sensitive?: true
    attribute :return_to, :string, allow_nil?: false, public?: true, default: "/"
    attribute :expires_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :consumed_at, :utc_datetime_usec, public?: true
    create_timestamp :inserted_at, public?: true
  end

  actions do
    defaults [:read]

    create :begin do
      accept [:state_hash, :code_verifier, :return_to, :expires_at]
    end

    update :consume do
      accept []
      change atomic_update(:consumed_at, expr(now()))
    end

    destroy :discard
  end

  identities do
    identity :state_hash, [:state_hash]
  end
end
