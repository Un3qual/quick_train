defmodule QuickTrain.EnterpriseIdentity.DirectoryUser do
  @moduledoc "Links a provider directory user to a global user and enterprise membership."

  use Ash.Resource,
    domain: QuickTrain.EnterpriseIdentity,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshGraphql.Resource]

  alias QuickTrain.Accounts.User

  alias QuickTrain.EnterpriseIdentity.{
    DirectoryGroup,
    DirectoryMembership,
    EnterpriseConnection
  }

  alias QuickTrain.Organizations.Membership

  postgres do
    table "directory_users"
    repo QuickTrain.Repo

    identity_index_names connection_external:
                           "directory_users_enterprise_connection_external_index"
  end

  graphql do
    type :directory_user
  end

  attributes do
    uuid_primary_key :id

    attribute :external_id, :string, allow_nil?: false, public?: true
    attribute :status, :string, allow_nil?: false, public?: true, default: "active"
    attribute :profile, :map, allow_nil?: false, public?: true, default: %{}

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :enterprise_connection, EnterpriseConnection,
      allow_nil?: false,
      attribute_public?: true,
      public?: true

    belongs_to :membership, Membership,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :user, User,
      allow_nil?: false,
      attribute_public?: true,
      public?: true

    has_many :directory_memberships, DirectoryMembership, public?: true

    has_many :directory_groups, DirectoryGroup,
      through: [:directory_memberships, :directory_group],
      public?: true
  end

  actions do
    defaults [:read]

    create :link do
      accept [
        :enterprise_connection_id,
        :membership_id,
        :user_id,
        :external_id,
        :status,
        :profile
      ]

      upsert? true
      upsert_identity :connection_external
      upsert_fields [:membership_id, :user_id, :status, :profile]
      return_skipped_upsert? true
      validate QuickTrain.EnterpriseIdentity.DirectoryUser.Validations.IdentityScope
    end

    update :set_status do
      accept [:status]
    end

    update :deprovision do
      accept []
      change set_attribute(:status, "inactive")
      change QuickTrain.EnterpriseIdentity.DirectoryUser.Changes.DeactivateMembership
    end
  end

  identities do
    identity :connection_external, [:enterprise_connection_id, :external_id]
  end
end
