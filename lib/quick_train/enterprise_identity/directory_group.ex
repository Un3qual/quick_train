defmodule QuickTrain.EnterpriseIdentity.DirectoryGroup do
  @moduledoc false

  use Ash.Resource,
    domain: QuickTrain.EnterpriseIdentity.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshGraphql.Resource]

  alias QuickTrain.Accounts.User
  alias QuickTrain.EnterpriseIdentity.{Directory, DirectoryMembership}

  postgres do
    table "directory_groups"
    repo QuickTrain.Repo

    unique_index_names [
      {[:directory_id, :external_id], "directory_groups_directory_external_index"}
    ]
  end

  graphql do
    type :directory_group
  end

  attributes do
    uuid_primary_key :id

    attribute :external_id, :string, allow_nil?: false, public?: true
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :status, :string, allow_nil?: false, public?: true, default: "active"

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :directory, Directory,
      allow_nil?: false,
      public?: true

    has_many :directory_memberships, DirectoryMembership

    has_many :users, User, through: [:directory_memberships, :directory_user, :user], public?: true
  end

  actions do
    defaults [:read, :create, :update]
  end

  identities do
    identity :directory_external, [:directory_id, :external_id]
  end
end
