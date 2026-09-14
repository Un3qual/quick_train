defmodule QuickTrain.Tasks.Attempt do
  @moduledoc "Scoped collection attempt evidence."
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

    attribute :request_key, :uuid, public?: true, allow_nil?: false

    attribute :operation, :atom,
      public?: true,
      allow_nil?: false,
      constraints: [one_of: [:fetch, :assign, :follow_up]]

    attribute :state, :atom,
      public?: true,
      allow_nil?: false,
      constraints: [
        one_of: [:claimed, :assigned, :in_progress, :submitted, :expired, :released, :cancelled]
      ]

    attribute :deadline, :utc_datetime_usec, public?: true, allow_nil?: false
    attribute :started_at, :utc_datetime_usec, public?: true, allow_nil?: true
    attribute :terminal_at, :utc_datetime_usec, public?: true, allow_nil?: true
    timestamps()
  end

  relationships do
    has_many :offered_questions, QuickTrain.Tasks.AttemptQuestion,
      destination_attribute: :attempt_id,
      public?: true

    has_many :input_presentations, QuickTrain.Tasks.AttemptInputPresentation,
      destination_attribute: :attempt_id,
      public?: true

    has_one :response, QuickTrain.Tasks.Response,
      destination_attribute: :attempt_id,
      public?: true

    belongs_to :organization, QuickTrain.Organizations.Organization,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :project, QuickTrain.Projects.Project, allow_nil?: false, attribute_public?: true

    belongs_to :form_version, QuickTrain.Forms.FormVersion,
      allow_nil?: false,
      attribute_public?: true,
      public?: true

    belongs_to :task, QuickTrain.Tasks.Task,
      allow_nil?: false,
      attribute_public?: true,
      public?: true

    belongs_to :worker, QuickTrain.Accounts.User, allow_nil?: false, attribute_public?: true
    belongs_to :requester, QuickTrain.Accounts.User, allow_nil?: false, attribute_public?: true
    belongs_to :predecessor, QuickTrain.Tasks.Attempt, allow_nil?: true, attribute_public?: true
  end

  actions do
    action :receipt, QuickTrain.Tasks.Receipt do
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      argument :attempt_id, :uuid, allow_nil?: false
      run QuickTrain.Tasks.ReadActions
    end

    action :work_bundle, :struct do
      constraints instance_of: QuickTrain.Tasks.Attempt
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      argument :attempt_id, :uuid, allow_nil?: false
      run QuickTrain.Tasks.ReadActions
    end

    read :list_audit do
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      filter expr(organization_id == ^arg(:organization_id) and project_id == ^arg(:project_id))
      prepare {QuickTrain.Tasks.ReadAccess.Prepare, mode: :audit}

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
      prepare {QuickTrain.Tasks.ReadAccess.Prepare, mode: :audit}
    end

    read :list_accepted do
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      filter expr(organization_id == ^arg(:organization_id) and project_id == ^arg(:project_id))
      prepare {QuickTrain.Tasks.ReadAccess.Prepare, mode: :accepted}

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
      prepare {QuickTrain.Tasks.ReadAccess.Prepare, mode: :accepted}
    end

    action :cancel, :struct do
      constraints instance_of: __MODULE__
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      argument :attempt_id, :uuid, allow_nil?: false
      run QuickTrain.Tasks.AttemptActions
    end

    action :release, :struct do
      constraints instance_of: __MODULE__
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      argument :attempt_id, :uuid, allow_nil?: false
      run QuickTrain.Tasks.AttemptActions
    end

    action :start, :struct do
      constraints instance_of: __MODULE__
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      argument :attempt_id, :uuid, allow_nil?: false
      run QuickTrain.Tasks.AttemptActions
    end

    action :fetch, QuickTrain.Tasks.AllocationResult do
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      argument :request_key, :uuid, allow_nil?: false
      run QuickTrain.Tasks.AttemptAllocation
    end

    action :assign, QuickTrain.Tasks.AllocationResult do
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      argument :request_key, :uuid, allow_nil?: false
      argument :worker_id, :uuid, allow_nil?: false
      run QuickTrain.Tasks.AttemptAllocation
    end

    action :follow_up, QuickTrain.Tasks.AllocationResult do
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      argument :request_key, :uuid, allow_nil?: false
      argument :worker_id, :uuid, allow_nil?: false
      argument :predecessor_id, :uuid, allow_nil?: false
      run QuickTrain.Tasks.AttemptAllocation
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
        :request_key,
        :operation,
        :state,
        :deadline,
        :started_at,
        :terminal_at,
        :organization_id,
        :project_id,
        :form_version_id,
        :task_id,
        :worker_id,
        :requester_id,
        :predecessor_id
      ]
    end

    update :update_internal do
      require_atomic? false
      accept [:state, :started_at, :terminal_at]
    end
  end

  policies do
    policy action([:work_bundle, :receipt]) do
      authorize_if actor_present()
    end

    policy action(:read) do
      authorize_if QuickTrain.Tasks.ReadAccess
    end

    policy action([:list_audit, :get_audit, :list_accepted, :get_accepted]) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "tasks.results.read"}
    end

    policy action([:start, :release]) do
      authorize_if actor_present()
    end

    policy action(:cancel) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "tasks.assign"}
    end

    policy action(:fetch) do
      authorize_if actor_present()
    end

    policy action([:assign, :follow_up]) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "tasks.assign"}
    end

    policy action([:create_internal, :update_internal]) do
      forbid_if always()
    end
  end

  graphql do
    type :attempt
    derive_filter? false
    derive_sort? false
    paginate_relationship_with offered_questions: :relay, input_presentations: :relay
    relationships [:form_version, :task, :offered_questions, :input_presentations, :response]
  end

  postgres do
    table "attempts"
    repo QuickTrain.Repo
    migration_defaults id: "fragment(\"gen_random_uuid()\")"

    references do
      reference :organization, on_delete: :restrict, name: "attempts_organization_scope_fkey"

      reference :project,
        on_delete: :restrict,
        name: "attempts_project_scope_fkey",
        match_with: [organization_id: :organization_id, form_version_id: :form_version_id]

      reference :form_version, on_delete: :restrict, name: "attempts_form_version_scope_fkey"

      reference :task,
        on_delete: :restrict,
        name: "attempts_task_scope_fkey",
        match_with: [project_id: :project_id, form_version_id: :form_version_id]

      reference :worker, on_delete: :restrict, name: "attempts_worker_scope_fkey"
      reference :requester, on_delete: :restrict, name: "attempts_requester_scope_fkey"

      reference :predecessor,
        on_delete: :restrict,
        name: "attempts_predecessor_scope_fkey",
        match_with: [task_id: :task_id, project_id: :project_id]
    end

    custom_indexes do
      index [:id, :task_id, :project_id, :form_version_id], unique: true, name: "attempts_scope_0"
      index [:id, :task_id, :project_id], unique: true, name: "attempts_scope_1"
      index [:task_id, :state, :deadline], unique: false, name: "attempts_scope_2"
      index [:project_id, :worker_id, :state], unique: false, name: "attempts_scope_3"
      index [:task_id, :worker_id], unique: false, name: "attempts_scope_4"

      index [:project_id, :worker_id],
        unique: true,
        where: "state IN ('claimed', 'assigned', 'in_progress')",
        name: "attempts_one_live_worker"
    end
  end

  identities do
    identity :request, [:project_id, :requester_id, :request_key]
  end
end
