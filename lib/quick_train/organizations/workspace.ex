defmodule QuickTrain.Organizations.Workspace do
  @moduledoc "An optional subdivision inside an organization."

  use Ash.Resource,
    domain: QuickTrain.Organizations.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "workspaces"
    repo QuickTrain.Repo
    unique_index_names [{[:organization_id, :slug], "workspaces_organization_slug_index"}]
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :slug, :string, allow_nil?: false, public?: true
    attribute :status, :string, allow_nil?: false, public?: true, default: "active"
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :organization, QuickTrain.Organizations.Organization do
      allow_nil? false
      attribute_public? true
    end
  end

  actions do
    defaults [:read, :create, :update]
  end

  identities do
    identity :organization_slug, [:organization_id, :slug]
  end
end
