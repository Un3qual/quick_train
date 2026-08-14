defmodule QuickTrain.EnterpriseIdentity.ExternalGroupRoleMapping do
  @moduledoc "Maps a directory group to an organization role."

  use Ash.Resource,
    domain: QuickTrain.EnterpriseIdentity.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "external_group_role_mappings"
    repo QuickTrain.Repo

    unique_index_names [
      {[:directory_group_id, :role_id], "external_group_role_mappings_group_role_index"}
    ]
  end

  attributes do
    uuid_primary_key :id
    attribute :directory_group_id, :uuid, allow_nil?: false, public?: true
    attribute :role_id, :uuid, allow_nil?: false, public?: true
    create_timestamp :inserted_at, public?: true
  end

  actions do
    defaults [:read, :create, :destroy]
  end

  identities do
    identity :group_role, [:directory_group_id, :role_id]
  end
end
