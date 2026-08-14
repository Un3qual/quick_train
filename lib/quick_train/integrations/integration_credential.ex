defmodule QuickTrain.Integrations.IntegrationCredential do
  @moduledoc "A reference to a secret-store entry; secret values never enter the database."

  use Ash.Resource,
    domain: QuickTrain.Integrations.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "integration_credentials"
    repo QuickTrain.Repo

    unique_index_names [
      {[:organization_id, :provider, :name], "integration_credentials_scope_index"}
    ]
  end

  attributes do
    uuid_primary_key :id
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :provider, :string, allow_nil?: false, public?: true
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :secret_reference, :string, allow_nil?: false, public?: true, sensitive?: true
    attribute :status, :string, allow_nil?: false, public?: true, default: "active"
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    defaults [:read, :create, :update, :destroy]
  end

  identities do
    identity :scope, [:organization_id, :provider, :name]
  end
end
