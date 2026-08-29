defmodule QuickTrain.Authorization.Role do
  @moduledoc "An organization-scoped collection of capabilities."

  use Ash.Resource,
    domain: QuickTrain.Authorization,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshGraphql.Resource]

  alias QuickTrain.Authorization.RoleCapability
  alias QuickTrain.Organizations.Organization

  postgres do
    table "roles"
    repo QuickTrain.Repo
    identity_index_names organization_key: "roles_organization_key_index"
  end

  graphql do
    type :role
  end

  attributes do
    uuid_primary_key :id

    attribute :key, :string, allow_nil?: false, public?: true
    attribute :name, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :organization, Organization,
      allow_nil?: false,
      attribute_public?: true

    has_many :role_capabilities, RoleCapability
  end

  actions do
    defaults [:read]

    create :create do
      accept [:organization_id, :key, :name]
    end

    create :bootstrap_first_manager_role do
      accept [:organization_id]
      change set_attribute(:key, "manager")
      change set_attribute(:name, "Manager")
    end
  end

  identities do
    identity :organization_key, [:organization_id, :key]
  end
end
