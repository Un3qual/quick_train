defmodule QuickTrain.Accounts.ExternalIdentity do
  @moduledoc "Links an OIDC provider subject to a global user account."

  use Ash.Resource,
    domain: QuickTrain.Accounts,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "external_identities"
    repo QuickTrain.Repo

    identity_index_names issuer_subject: "external_identities_issuer_subject_index",
                         user_issuer: "external_identities_user_issuer_index"
  end

  attributes do
    uuid_primary_key :id
    attribute :issuer, :string, allow_nil?: false, sensitive?: true
    attribute :subject, :string, allow_nil?: false, sensitive?: true
    attribute :status, :string, allow_nil?: false, default: "active"
    attribute :claims, :map, allow_nil?: false, sensitive?: true, default: %{}
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, QuickTrain.Accounts.User do
      allow_nil? false
      attribute_public? true
    end
  end

  actions do
    defaults [:read]

    create :create_identity do
      accept [:user_id, :issuer, :subject, :claims]
    end

    update :refresh do
      accept [:claims]
    end

    update :set_status do
      accept [:status]
    end
  end

  validations do
    validate one_of(:status, ~w(active inactive))
  end

  identities do
    identity :issuer_subject, [:issuer, :subject]
    identity :user_issuer, [:user_id, :issuer]
  end
end
