defmodule QuickTrain.Integrations.ExternalReference do
  @moduledoc "Maps an internal resource to a provider-owned identifier."

  use Ash.Resource,
    domain: QuickTrain.Integrations.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "external_references"
    repo QuickTrain.Repo

    unique_index_names [
      {[:provider, :external_type, :external_id], "external_references_provider_index"}
    ]
  end

  attributes do
    uuid_primary_key :id
    attribute :organization_id, :uuid, public?: true
    attribute :provider, :string, allow_nil?: false, public?: true
    attribute :external_type, :string, allow_nil?: false, public?: true
    attribute :external_id, :string, allow_nil?: false, public?: true
    attribute :internal_type, :string, allow_nil?: false, public?: true
    attribute :internal_id, :uuid, allow_nil?: false, public?: true
    create_timestamp :inserted_at, public?: true
  end

  actions do
    defaults [:read, :create, :destroy]
  end

  identities do
    identity :provider_reference, [:provider, :external_type, :external_id]
  end
end
