defmodule QuickTrain.Organizations.Organization do
  @moduledoc "An enterprise tenant that owns and manages application content."

  use Ash.Resource,
    domain: QuickTrain.Organizations.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshGraphql.Resource]

  alias QuickTrain.Accounts.User
  alias QuickTrain.Organizations.Membership
  alias QuickTrain.EnterpriseIdentity.{Directory, EnterpriseConnection}

  postgres do
    table "organizations"
    repo QuickTrain.Repo
    identity_index_names slug: "organizations_slug_index"
  end

  graphql do
    type :organization
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, allow_nil?: false, public?: true
    attribute :slug, :string, allow_nil?: false, public?: true
    attribute :status, :string, allow_nil?: false, public?: true, default: "active"

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    has_many :memberships, Membership

    has_many :users, User, through: [:memberships, :user], public?: true

    has_many :enterprise_connections, EnterpriseConnection, public?: true

    has_many :directories, Directory, through: [:enterprise_connections, :directories], public?: true
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:name]

      change set_attribute(:status, "active")
      change set_attribute(:slug, &String.trim/1)
    end

    update :update do
      accept [:name, :status]
    end
  end

  identities do
    identity :slug, [:slug]
  end
end
