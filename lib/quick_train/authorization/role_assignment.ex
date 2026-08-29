defmodule QuickTrain.Authorization.RoleAssignment do
  @moduledoc "Assigns an organization role to a user."

  use Ash.Resource,
    domain: QuickTrain.Authorization,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource]

  alias QuickTrain.Accounts.User
  alias QuickTrain.Authorization.Role
  alias QuickTrain.Organizations.{Membership, Organization}

  postgres do
    table "role_assignments"
    repo QuickTrain.Repo

    identity_index_names organization_user_role: "role_assignments_organization_user_role_index"
  end

  graphql do
    type :role_assignment
  end

  attributes do
    uuid_primary_key :id
    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :organization, Organization,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :user, User,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :role, Role,
      allow_nil?: false,
      attribute_public?: true
  end

  actions do
    defaults [:read]

    create :assign do
      accept [:organization_id, :user_id, :role_id]
    end

    create :bootstrap_first_manager_assignment do
      accept [:organization_id, :user_id, :role_id]
    end

    action :allowed?, :boolean do
      argument :user_id, :uuid, allow_nil?: false
      argument :organization_id, :uuid, allow_nil?: false
      argument :capability_key, :string, allow_nil?: false

      run QuickTrain.Authorization.RoleAssignment.Actions.Allowed
    end
  end

  policies do
    policy action_type(:create) do
      forbid_unless expr(
                      exists(
                        Membership,
                        organization_id == parent(organization_id) and user_id == parent(user_id) and
                          status == "active"
                      )
                    )

      forbid_unless expr(
                      exists(
                        Role,
                        id == parent(role_id) and organization_id == parent(organization_id)
                      )
                    )

      authorize_if always()
    end

    policy action(:allowed?) do
      authorize_if always()
    end
  end

  identities do
    identity :organization_user_role, [:organization_id, :user_id, :role_id]
  end
end
