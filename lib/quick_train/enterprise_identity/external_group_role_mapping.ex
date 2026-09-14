defmodule QuickTrain.EnterpriseIdentity.ExternalGroupRoleMapping do
  @moduledoc "Maps a directory group to an organization role."

  use Ash.Resource,
    domain: QuickTrain.EnterpriseIdentity,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshGraphql.Resource]

  alias QuickTrain.Authorization.Role
  alias QuickTrain.EnterpriseIdentity.DirectoryGroup

  postgres do
    migration_defaults id: "fragment(\"gen_random_uuid()\")"
    table "external_group_role_mappings"
    repo QuickTrain.Repo

    identity_index_names group_role: "external_group_role_mappings_group_role_index"
  end

  graphql do
    type :external_group_role_mapping
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      generated?: true,
      public?: true,
      writable?: false

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
    defaults [:read]

    create :map do
      accept [:directory_group_id, :role_id]
      upsert? true
      upsert_identity :group_role
      upsert_fields []
      return_skipped_upsert? true
      validate QuickTrain.EnterpriseIdentity.ExternalGroupRoleMapping.Validations.MappingScope
    end

    destroy :unmap
  end

  identities do
    identity :group_role, [:directory_group_id, :role_id]
  end
end
