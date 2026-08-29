defmodule QuickTrain.Organizations.Membership do
  @moduledoc "Relates a global user to an organization without changing the user's account type."

  use Ash.Resource,
    domain: QuickTrain.Organizations,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshGraphql.Resource]

  alias QuickTrain.Accounts.User
  alias QuickTrain.Organizations.Organization

  require Ash.Query

  postgres do
    table "organization_memberships"
    repo QuickTrain.Repo

    identity_index_names organization_user: "organization_memberships_organization_user_index"
  end

  graphql do
    derive_filter? false
    type :organization_membership
  end

  attributes do
    uuid_primary_key :id
    attribute :status, :string, allow_nil?: false, public?: true, default: "active"
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :organization, Organization,
      allow_nil?: false,
      public?: true

    belongs_to :user, User,
      allow_nil?: false,
      public?: true
  end

  actions do
    defaults [:read]

    action :member?, :boolean do
      argument :organization_id, :uuid, allow_nil?: false
      argument :user_id, :uuid, allow_nil?: false

      run fn input, _context ->
        input.resource
        |> Ash.Query.filter(
          organization_id == ^input.arguments.organization_id and
            user_id == ^input.arguments.user_id and status == "active"
        )
        |> Ash.exists(authorize?: false)
      end
    end

    create :add do
      accept [:organization_id, :user_id, :status]
      upsert? true
      upsert_identity :organization_user
      upsert_fields [:status]
      return_skipped_upsert? true
    end

    create :bootstrap_first_manager_membership do
      accept [:organization_id, :user_id]
      change set_attribute(:status, "active")
    end

    update :deactivate do
      accept []
      change set_attribute(:status, "inactive")
    end
  end

  identities do
    identity :organization_user, [:organization_id, :user_id]
  end
end
