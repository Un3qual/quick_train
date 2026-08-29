defmodule QuickTrain.Accounts.OidcLoginTransaction do
  @moduledoc "Short-lived server-side OIDC state and PKCE material."

  use Ash.Resource,
    domain: QuickTrain.Accounts,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "oidc_login_transactions"
    repo QuickTrain.Repo
    identity_index_names state_hash: "oidc_login_transactions_state_hash_index"

    custom_indexes do
      index [:status, :expires_at], name: "oidc_login_transactions_status_expires_at_index"
      index [:retain_until], name: "oidc_login_transactions_retain_until_index"
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :state_hash, :binary, allow_nil?: false, sensitive?: true
    attribute :nonce_hash, :binary, allow_nil?: false, sensitive?: true
    attribute :code_verifier, :string, allow_nil?: false, sensitive?: true
    attribute :redemption_secret_hash, :binary, allow_nil?: false, sensitive?: true
    attribute :callback_key, :string, allow_nil?: false
    attribute :callback_uri, :string, allow_nil?: false, sensitive?: true
    attribute :status, :string, allow_nil?: false, default: "pending"
    attribute :expires_at, :utc_datetime_usec, allow_nil?: false
    attribute :retain_until, :utc_datetime_usec, allow_nil?: false
    attribute :exchange_started_at, :utc_datetime_usec
    attribute :consumed_at, :utc_datetime_usec
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  actions do
    defaults [:read]

    action :begin_login, :map do
      argument :callback_key, :string, allow_nil?: false
      argument :network_source, :string, allow_nil?: false

      run QuickTrain.Accounts.OidcLoginTransaction.Actions.BeginLogin
    end

    action :exchange_login, :map do
      argument :code, :string, allow_nil?: false
      argument :state, :string, allow_nil?: false
      argument :client_proof, :string, allow_nil?: false

      run QuickTrain.Accounts.OidcLoginTransaction.Actions.ExchangeLogin
    end

    create :begin do
      accept [
        :state_hash,
        :nonce_hash,
        :code_verifier,
        :redemption_secret_hash,
        :callback_key,
        :callback_uri,
        :expires_at,
        :retain_until
      ]
    end

    update :claim do
      accept []
      validate attribute_equals(:status, "pending")
      validate compare(:expires_at, greater_than: &DateTime.utc_now/0)
      change set_attribute(:status, "exchanging")
      change atomic_update(:exchange_started_at, expr(now()))
    end

    update :consume do
      accept []
      validate attribute_equals(:status, "exchanging")
      change set_attribute(:status, "consumed")
      change atomic_update(:consumed_at, expr(now()))
    end

    destroy :discard
  end

  validations do
    validate one_of(:status, ~w(pending exchanging consumed))
  end

  identities do
    identity :state_hash, [:state_hash]
  end
end
