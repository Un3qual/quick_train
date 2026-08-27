defmodule QuickTrain.EnterpriseIdentity.Directory do
  @moduledoc "A directory synchronized through an enterprise connection."

  use Ash.Resource,
    domain: QuickTrain.EnterpriseIdentity,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshGraphql.Resource]

  alias QuickTrain.Accounts.User
  alias QuickTrain.EnterpriseIdentity.{DirectoryGroup, EnterpriseConnection}

  postgres do
    table "directories"
    repo QuickTrain.Repo

    identity_index_names connection_external: "directories_enterprise_connection_external_index"
  end

  graphql do
    type :directory
  end

  attributes do
    uuid_primary_key :id

    attribute :external_id, :string, allow_nil?: false, public?: true
    attribute :status, :string, allow_nil?: false, public?: true, default: "active"
    attribute :last_synced_at, :utc_datetime_usec, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :enterprise_connection, EnterpriseConnection, allow_nil?: false, public?: true

    has_many :directory_groups, DirectoryGroup, public?: true
    has_many :users, User, through: [:directory_groups, :users], public?: true
  end

  actions do
    defaults [:read]

    create :create do
      accept [:enterprise_connection_id, :external_id, :status, :last_synced_at]
    end

    update :update do
      accept [:status, :last_synced_at]
    end
  end

  identities do
    identity :connection_external, [:enterprise_connection_id, :external_id]
  end
end
