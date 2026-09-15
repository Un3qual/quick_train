defmodule QuickTrain.Projects.ProjectWorkerAccess do
  @moduledoc "Organization-scoped project configuration."
  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Projects,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshGraphql.Resource],
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id

    attribute :disposition, :atom,
      public?: true,
      allow_nil?: false,
      constraints: [one_of: [:allow, :block]]

    timestamps()
  end

  relationships do
    belongs_to :project, QuickTrain.Projects.Project, allow_nil?: false, attribute_public?: true
    belongs_to :user, QuickTrain.Accounts.User, allow_nil?: false, attribute_public?: true
  end

  actions do
    read :read do
      primary? true

      pagination keyset?: true,
                 required?: false,
                 default_limit: 50,
                 max_page_size: 100,
                 stable_sort: [inserted_at: :asc, id: :asc]
    end

    read :list_scoped do
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false

      filter expr(
               project_id == ^arg(:project_id) and
                 project.organization_id == ^arg(:organization_id)
             )

      pagination keyset?: true,
                 required?: true,
                 default_limit: 50,
                 max_page_size: 100,
                 stable_sort: [inserted_at: :asc, id: :asc]
    end

    read :get_for_remove do
      get? true
      argument :project_id, :uuid, allow_nil?: false
      argument :user_id, :uuid, allow_nil?: false

      filter expr(
               project_id == ^arg(:project_id) and
                 user_id == ^arg(:user_id)
             )
    end

    create :set do
      upsert? true
      upsert_identity :project_user
      upsert_fields [:disposition, :updated_at]
      argument :organization_id, :uuid, allow_nil?: false
      accept [:project_id, :user_id, :disposition]
      change Module.concat(["QuickTrain.Projects.Changes.ConfigureChild"])
    end

    destroy :remove do
      argument :organization_id, :uuid, allow_nil?: false
      require_atomic? false
      change Module.concat(["QuickTrain.Projects.Changes.ConfigureChild"])
    end
  end

  policies do
    policy action(:get_for_remove) do
      authorize_if expr(
                     exists(
                       project.reader_role_assignments,
                       user_id == ^actor(:id) and
                         exists(role.role_capabilities, capability.key == "projects.manage")
                     )
                   )
    end

    policy action([:set, :remove]) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "projects.manage"}
    end

    policy action(:read) do
      forbid_unless actor_attribute_equals(:status, "active")
      authorize_if relates_to_actor_via([:project, :reader_role_assignments, :user])
    end

    policy action(:read) do
      authorize_if accessing_from(Module.concat(["QuickTrain.Projects.Project"]), :worker_access)
    end

    policy action(:list_scoped) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "projects.read"}
    end
  end

  graphql do
    type :project_worker_access
    derive_filter? false
    derive_sort? false
    relationships []
  end

  postgres do
    table "project_worker_access"
    repo QuickTrain.Repo

    references do
      reference :project, on_delete: :restrict
      reference :user, on_delete: :restrict
    end

    custom_indexes do
      index [:id, :project_id], unique: true
    end

    check_constraints do
      check_constraint :disposition, "project_worker_access_disposition_check",
        check: "disposition IN ('allow', 'block')"
    end
  end

  identities do
    identity :project_user, [:project_id, :user_id]
  end
end
