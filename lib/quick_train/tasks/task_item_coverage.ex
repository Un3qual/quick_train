defmodule QuickTrain.Tasks.TaskItemCoverage do
  @moduledoc "Scoped collection task item coverage evidence."
  use Ash.Resource,
    primary_read_warning?: false,
    otp_app: :quick_train,
    domain: QuickTrain.Tasks,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      generated?: true,
      writable?: false

    attribute :exposures, :integer,
      public?: true,
      allow_nil?: false,
      default: 0,
      constraints: [min: 0]

    timestamps()
  end

  relationships do
    has_many :issued_inputs, QuickTrain.Tasks.TaskInput,
      source_attribute: :project_item_id,
      destination_attribute: :project_item_id

    belongs_to :organization, QuickTrain.Organizations.Organization,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :project, QuickTrain.Projects.Project, allow_nil?: false, attribute_public?: true

    belongs_to :form_version, QuickTrain.Forms.FormVersion,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :project_item, QuickTrain.Projects.ProjectItem,
      allow_nil?: false,
      attribute_public?: true
  end

  actions do
    for {mode, list_action, get_action} <- [
          {:audit, :list_audit, :get_audit},
          {:accepted, :list_accepted, :get_accepted}
        ] do
      read list_action do
        argument :organization_id, :uuid, allow_nil?: false
        argument :project_id, :uuid, allow_nil?: false
        filter expr(organization_id == ^arg(:organization_id) and project_id == ^arg(:project_id))
        prepare {Module.concat(["QuickTrain.Tasks.ReadAccess.Prepare"]), mode: mode}

        pagination keyset?: true,
                   required?: true,
                   default_limit: 50,
                   max_page_size: 100,
                   stable_sort: [inserted_at: :asc, id: :asc]
      end

      read get_action do
        get? true
        argument :id, :uuid, allow_nil?: false
        filter expr(id == ^arg(:id))
        argument :organization_id, :uuid, allow_nil?: false
        argument :project_id, :uuid, allow_nil?: false
        filter expr(organization_id == ^arg(:organization_id) and project_id == ^arg(:project_id))
        prepare {Module.concat(["QuickTrain.Tasks.ReadAccess.Prepare"]), mode: mode}
      end
    end

    read :read do
      primary? true

      prepare build(sort: [id: :asc])

      pagination keyset?: true,
                 required?: false,
                 default_limit: 50,
                 max_page_size: 100,
                 stable_sort: [id: :asc]
    end

    create :create_internal do
      accept [:exposures, :organization_id, :project_id, :form_version_id, :project_item_id]
    end

    update :update_internal do
      accept [:exposures]
    end
  end

  policies do
    policy action(:read) do
      authorize_if Module.concat(["QuickTrain.Tasks.ReadAccess"])
    end

    policy action([:list_audit, :get_audit, :list_accepted, :get_accepted]) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "tasks.results.read"}
    end

    policy action([:create_internal, :update_internal]) do
      forbid_if always()
    end
  end

  graphql do
    type :task_item_coverage
    attribute_types exposures: :string
    derive_filter? false
    derive_sort? false
    relationships []
  end

  postgres do
    table "task_item_coverage"
    repo QuickTrain.Repo
    migration_defaults id: "fragment(\"gen_random_uuid()\")"
    migration_types exposures: :bigint

    references do
      reference :organization,
        on_delete: :restrict,
        name: "task_item_coverage_organization_scope_fkey"

      reference :project,
        on_delete: :restrict,
        name: "task_item_coverage_project_scope_fkey",
        match_with: [organization_id: :organization_id, form_version_id: :form_version_id]

      reference :form_version,
        on_delete: :restrict,
        name: "task_item_coverage_form_version_scope_fkey"

      reference :project_item,
        on_delete: :restrict,
        name: "task_item_coverage_project_item_scope_fkey",
        match_with: [project_id: :project_id]
    end
  end

  identities do
    identity :project_item, [:project_item_id]
  end
end
