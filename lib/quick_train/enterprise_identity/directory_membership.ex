defmodule QuickTrain.EnterpriseIdentity.DirectoryMembership do
  @moduledoc false

  use Ash.Resource,
    domain: QuickTrain.EnterpriseIdentity.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshGraphql.Resource]

  alias QuickTrain.EnterpriseIdentity.{DirectoryUser, DirectoryGroup}

  postgres do
    table "directory_memberships"
    repo QuickTrain.Repo

    unique_index_names [
      {[:directory_user_id, :directory_group_id], "directory_memberships_user_group_index"}
    ]
  end

   graphql do
    type :directory_membership
  end

  attributes do
    uuid_primary_key :id
    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :directory_user, DirectoryUser,
      allow_nil?: false,
      public?: true

    belongs_to :directory_group, DirectoryGroup,
      allow_nil?: false,
      public?: true
  end

  actions do
    defaults [:read, :create, :destroy]
  end

  identities do
    identity :user_group, [:directory_user_id, :directory_group_id]
  end
end
