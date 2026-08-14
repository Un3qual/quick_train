defmodule QuickTrain.Organizations.Organization do
  @moduledoc "An enterprise tenant that owns and manages application content."

  use Ash.Resource,
    domain: QuickTrain.Organizations.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "organizations"
    repo QuickTrain.Repo
    identity_index_names slug: "organizations_slug_index"
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :slug, :string, allow_nil?: false, public?: true
    attribute :status, :string, allow_nil?: false, public?: true, default: "active"
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    defaults [:read]

    create :create do
      accept [:name, :slug, :status]
    end

    update :update do
      accept [:name, :status]
    end
  end

  identities do
    identity :slug, [:slug]
  end
end
