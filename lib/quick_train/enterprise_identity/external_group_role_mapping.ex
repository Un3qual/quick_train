defmodule QuickTrain.EnterpriseIdentity.ExternalGroupRoleMapping do
  @moduledoc "Maps a directory group to an organization role."

  use Ash.Resource,
    domain: QuickTrain.EnterpriseIdentity,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshGraphql.Resource]

  alias QuickTrain.EnterpriseIdentity.DirectoryGroup
  alias QuickTrain.Authorization.Role

  postgres do
    table "external_group_role_mappings"
    repo QuickTrain.Repo

    unique_index_names [
      {[:directory_group_id, :role_id], "external_group_role_mappings_group_role_index"}
    ]
  end

  graphql do
    type :external_group_role_mapping
  end

  attributes do
    uuid_primary_key :id

    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :directory_group, DirectoryGroup,
      allow_nil?: false,
      public?: true

    belongs_to :role, Role,
      allow_nil?: false,
      public?: true
  end

  actions do
    defaults [:read, :create, :destroy]
  end

  identities do
    identity :group_role, [:directory_group_id, :role_id]
  end
end
