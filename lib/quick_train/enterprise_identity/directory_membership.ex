defmodule QuickTrain.EnterpriseIdentity.DirectoryMembership do
  @moduledoc false

  use Ash.Resource,
    domain: QuickTrain.EnterpriseIdentity.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "directory_memberships"
    repo QuickTrain.Repo

    unique_index_names [
      {[:directory_user_id, :directory_group_id], "directory_memberships_user_group_index"}
    ]
  end

  attributes do
    uuid_primary_key :id
    attribute :directory_user_id, :uuid, allow_nil?: false, public?: true
    attribute :directory_group_id, :uuid, allow_nil?: false, public?: true
    create_timestamp :inserted_at, public?: true
  end

  actions do
    defaults [:read, :create, :destroy]
  end

  identities do
    identity :user_group, [:directory_user_id, :directory_group_id]
  end
end
