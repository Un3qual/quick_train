defmodule QuickTrain.Tasks.Task do
  @moduledoc "Scoped collection task evidence."
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

    attribute :canonical_key, :binary, public?: false, allow_nil?: false
    attribute :canonical_membership, :binary, public?: false, allow_nil?: false

    attribute :state, :atom,
      public?: true,
      allow_nil?: false,
      default: :open,
      constraints: [one_of: [:open, :satisfied, :needs_attention, :cancelled]]

    timestamps()
  end

  relationships do
    has_many :progress, QuickTrain.Tasks.TaskQuestionProgress,
      destination_attribute: :task_id,
      public?: true

    has_many :inputs, QuickTrain.Tasks.TaskInput, destination_attribute: :task_id, public?: true
    has_many :attempts, QuickTrain.Tasks.Attempt, destination_attribute: :task_id, public?: true

    has_many :outcomes, QuickTrain.Tasks.QuestionResponse,
      destination_attribute: :task_id,
      public?: true

    belongs_to :organization, QuickTrain.Organizations.Organization,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :project, QuickTrain.Projects.Project, allow_nil?: false, attribute_public?: true

    belongs_to :form_version, QuickTrain.Forms.FormVersion,
      allow_nil?: false,
      attribute_public?: true,
      public?: true

    belongs_to :explicit_group, QuickTrain.Projects.ExplicitGroup,
      allow_nil?: true,
      attribute_public?: true
  end

  actions do
    read :list_audit do
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      filter expr(organization_id == ^arg(:organization_id) and project_id == ^arg(:project_id))
      prepare {Module.concat(["QuickTrain.Tasks.ReadAccess.Prepare"]), mode: :audit}

      pagination keyset?: true,
                 required?: true,
                 default_limit: 50,
                 max_page_size: 100,
                 stable_sort: [inserted_at: :asc, id: :asc]
    end

    read :get_audit do
      get? true
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id))
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      filter expr(organization_id == ^arg(:organization_id) and project_id == ^arg(:project_id))
      prepare {Module.concat(["QuickTrain.Tasks.ReadAccess.Prepare"]), mode: :audit}
    end

    read :list_accepted do
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      filter expr(organization_id == ^arg(:organization_id) and project_id == ^arg(:project_id))
      prepare {Module.concat(["QuickTrain.Tasks.ReadAccess.Prepare"]), mode: :accepted}

      pagination keyset?: true,
                 required?: true,
                 default_limit: 50,
                 max_page_size: 100,
                 stable_sort: [inserted_at: :asc, id: :asc]
    end

    read :get_accepted do
      get? true
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id))
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      filter expr(organization_id == ^arg(:organization_id) and project_id == ^arg(:project_id))
      prepare {Module.concat(["QuickTrain.Tasks.ReadAccess.Prepare"]), mode: :accepted}
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
      accept [
        :canonical_key,
        :canonical_membership,
        :state,
        :organization_id,
        :project_id,
        :form_version_id,
        :explicit_group_id
      ]
    end

    update :update_internal do
      require_atomic? false
      accept [:state]
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
    type :task
    derive_filter? false
    derive_sort? false

    paginate_relationship_with progress: :relay,
                               inputs: :relay,
                               attempts: :relay,
                               outcomes: :relay

    relationships [:inputs, :attempts, :outcomes, :form_version, :progress]
  end

  postgres do
    table "tasks"
    repo QuickTrain.Repo
    migration_defaults id: "fragment(\"gen_random_uuid()\")"

    references do
      reference :organization, on_delete: :restrict, name: "tasks_organization_scope_fkey"

      reference :project,
        on_delete: :restrict,
        name: "tasks_project_scope_fkey",
        match_with: [organization_id: :organization_id, form_version_id: :form_version_id]

      reference :form_version, on_delete: :restrict, name: "tasks_form_version_scope_fkey"

      reference :explicit_group,
        on_delete: :restrict,
        name: "tasks_explicit_group_scope_fkey",
        match_with: [project_id: :project_id, form_version_id: :form_version_id]
    end

    custom_indexes do
      index [:id, :project_id, :form_version_id], unique: true, name: "tasks_scope_0"
    end
  end

  identities do
    identity :canonical_group, [:project_id, :canonical_key]
  end
end
