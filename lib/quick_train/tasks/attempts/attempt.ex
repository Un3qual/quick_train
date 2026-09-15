defmodule QuickTrain.Tasks.Attempts.Attempt do
  @moduledoc "Scoped collection attempt evidence."
  use Ash.Resource,
    primary_read_warning?: false,
    otp_app: :quick_train,
    domain: QuickTrain.Tasks,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias QuickTrain.Accounts.User
  alias QuickTrain.Authorization.Checks.OrganizationCapability
  alias QuickTrain.Forms.FormVersion
  alias QuickTrain.Organizations.Organization
  alias QuickTrain.Projects.Project
  alias QuickTrain.Repo
  alias QuickTrain.Tasks.Attempts.{AllocationResult, AttemptInputPresentation, Receipt}
  alias QuickTrain.Tasks.Responses.Inputs.AnswerInput
  alias QuickTrain.Tasks.Responses.QuestionResponse
  alias QuickTrain.Tasks.Task

  attributes do
    uuid_primary_key :id

    attribute :request_key, :uuid, public?: true, allow_nil?: false

    attribute :operation, :atom,
      public?: true,
      allow_nil?: false,
      constraints: [one_of: [:fetch, :assign]]

    attribute :state, :atom,
      public?: true,
      allow_nil?: false,
      constraints: [
        one_of: [:claimed, :assigned, :in_progress, :submitted, :expired, :released, :cancelled]
      ]

    attribute :deadline, :utc_datetime_usec, public?: true, allow_nil?: false
    attribute :started_at, :utc_datetime_usec, public?: true, allow_nil?: true
    attribute :terminal_at, :utc_datetime_usec, public?: true, allow_nil?: true

    attribute :revision, :integer,
      public?: true,
      allow_nil?: false,
      default: 0,
      constraints: [min: 0]

    timestamps()
  end

  relationships do
    has_many :input_presentations, AttemptInputPresentation,
      destination_attribute: :attempt_id,
      public?: true

    has_many :outcomes, QuestionResponse,
      destination_attribute: :attempt_id,
      public?: true

    belongs_to :organization, Organization,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :project, Project, allow_nil?: false, attribute_public?: true

    belongs_to :form_version, FormVersion,
      allow_nil?: false,
      attribute_public?: true,
      public?: true

    belongs_to :task, Task,
      allow_nil?: false,
      attribute_public?: true,
      public?: true

    belongs_to :worker, User, allow_nil?: false, attribute_public?: true
    belongs_to :requester, User, allow_nil?: false, attribute_public?: true
  end

  calculations do
    calculate :skip_allowed, :boolean, expr(project.skip_allowed), public?: true
    calculate :reason_required, :boolean, expr(project.reason_required), public?: true
  end

  actions do
    update :submit do
      accept []
      require_atomic? false
      change Module.concat(["QuickTrain.Tasks.Responses.Changes.Submit"])
    end

    action :save_question, :struct do
      transaction? true
      constraints instance_of: __MODULE__
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      argument :attempt_id, :uuid, allow_nil?: false
      argument :question_id, :uuid, allow_nil?: false
      argument :expected_revision, :integer, allow_nil?: false, constraints: [min: 0]
      argument :answer, AnswerInput, allow_nil?: false
      run Module.concat(["QuickTrain.Tasks.Responses.ResponseDraft"])
    end

    read :read_work_bundle do
      get? true
      transaction? true
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      argument :attempt_id, :uuid, allow_nil?: false

      filter expr(
               id == ^arg(:attempt_id) and project_id == ^arg(:project_id) and
                 organization_id == ^arg(:organization_id)
             )

      prepare Module.concat(["QuickTrain.Tasks.Attempts.WorkBundle"])
    end

    action :receipt, Receipt do
      transaction? true
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      argument :attempt_id, :uuid, allow_nil?: false
      run Module.concat(["QuickTrain.Tasks.Access.ReadActions"])
    end

    read :get_for_update do
      get? true
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      argument :attempt_id, :uuid, allow_nil?: false

      filter expr(
               id == ^arg(:attempt_id) and project_id == ^arg(:project_id) and
                 organization_id == ^arg(:organization_id)
             )
    end

    action :fetch, AllocationResult do
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      argument :request_key, :uuid, allow_nil?: false
      run Module.concat(["QuickTrain.Tasks.Attempts.AttemptAllocation"])
    end

    action :assign, AllocationResult do
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      argument :request_key, :uuid, allow_nil?: false
      argument :worker_id, :uuid, allow_nil?: false
      run Module.concat(["QuickTrain.Tasks.Attempts.AttemptAllocation"])
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
        :requester_id
      ]
    end

    for action <- [:start, :release, :cancel, :expire] do
      update action do
        public? action != :expire
        accept []
        require_atomic? false
        change Module.concat(["QuickTrain.Tasks.Attempts.Changes.Transition"])
      end
    end

    update :revise do
      accept []
      require_atomic? false
      change Module.concat(["QuickTrain.Tasks.Responses.Changes.DraftEvidence"])
      change atomic_update(:revision, expr(revision + 1))
    end

    update :update_internal do
      accept [:state, :started_at, :terminal_at]
    end
  end

  policies do
    policy action(:get_for_update) do
      forbid_unless actor_attribute_equals(:status, "active")
      authorize_if Module.concat(["QuickTrain.Tasks.Access.ReadAccess"])

      authorize_if {OrganizationCapability, capability: "tasks.assign"}
    end

    policy action([:read_work_bundle, :receipt]) do
      authorize_if actor_present()
    end

    policy action([:save_question, :submit]) do
      authorize_if actor_present()
    end

    policy action(:read) do
      authorize_if Module.concat(["QuickTrain.Tasks.Access.ReadAccess"])
    end

    policy action([:start, :release]) do
      authorize_if actor_present()
    end

    policy action(:cancel) do
      authorize_if {OrganizationCapability, capability: "tasks.assign"}
    end

    policy action(:fetch) do
      authorize_if actor_present()
    end

    policy action([:assign]) do
      authorize_if {OrganizationCapability, capability: "tasks.assign"}
    end

    policy action([:create_internal, :update_internal, :revise]) do
      forbid_if always()
    end
  end

  graphql do
    type :attempt
    derive_filter? false
    derive_sort? false

    paginate_relationship_with input_presentations: :relay,
                               outcomes: :relay

    relationships [:form_version, :task, :input_presentations, :outcomes]
  end

  postgres do
    table "attempts"
    repo Repo
    migration_types revision: :bigint

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
