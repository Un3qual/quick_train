defmodule QuickTrain.Authorization.RoleCapability do
  @moduledoc false

  use Ash.Resource,
    domain: QuickTrain.Authorization,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshGraphql.Resource]

  alias QuickTrain.Authorization.{Role, Capability}

  postgres do
    table "role_capabilities"
    repo QuickTrain.Repo
    unique_index_names [{[:role_id, :capability_id], "role_capabilities_role_capability_index"}]
  end

  graphql do
    type :role_capability
  end

  attributes do
    uuid_primary_key :id

    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :role, Role,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :capability, Capability,
      allow_nil?: false,
      attribute_public?: true
  end

  actions do
    defaults [:read]

    create :grant do
      accept [:role_id, :capability_id]
    end
  end

  identities do
    identity :role_capability, [:role_id, :capability_id]
  end
end
