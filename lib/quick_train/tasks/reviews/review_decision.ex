defmodule QuickTrain.Tasks.Reviews.ReviewDecision do
  @moduledoc "Scoped collection review decision evidence."
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
  alias QuickTrain.Forms.Questions.QuestionDefinition
  alias QuickTrain.Organizations.Organization
  alias QuickTrain.Projects.Project
  alias QuickTrain.Repo
  alias QuickTrain.Tasks.Access.ReadAccess
  alias QuickTrain.Tasks.Responses.QuestionResponse
  alias QuickTrain.Tasks.Reviews.QuestionReview.Input, as: ReviewInput
  alias QuickTrain.Tasks.Task

  attributes do
    uuid_primary_key :id

    attribute :origin, :atom,
      public?: true,
      allow_nil?: false,
      constraints: [one_of: [:system, :human]]

    attribute :verdict, :atom,
      public?: true,
      allow_nil?: false,
      constraints: [one_of: [:accept, :reject]]

    attribute :number, :integer, public?: true, allow_nil?: false, constraints: [min: 1]
    attribute :request_key, :uuid, public?: true, allow_nil?: true

    attribute :reason, :string,
      public?: true,
      allow_nil?: true,
      constraints: [trim?: false, allow_empty?: true]

    timestamps()
  end

  relationships do
    belongs_to :organization, Organization,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :project, Project, allow_nil?: false, attribute_public?: true

    belongs_to :form_version, FormVersion,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :task, Task, allow_nil?: false, attribute_public?: true

    belongs_to :question, QuestionDefinition,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :question_response, QuestionResponse,
      allow_nil?: false,
      public?: true,
      attribute_public?: true

    belongs_to :requester, User, allow_nil?: true, attribute_public?: true

    belongs_to :predecessor, __MODULE__,
      allow_nil?: true,
      attribute_public?: true
  end

  actions do
    action :decide, :struct do
      constraints instance_of: __MODULE__
      transaction? true
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      argument :question_response_id, :uuid, allow_nil?: false
      argument :request_key, :uuid, allow_nil?: false
      argument :expected_predecessor_id, :uuid
      argument :verdict, :atom, allow_nil?: false, constraints: [one_of: [:accept, :reject]]
      argument :reason, :string, constraints: [trim?: false, allow_empty?: true]
      run {Module.concat(["QuickTrain.Tasks.Reviews.QuestionReview"]), []}
    end

    action :review_batch, {:array, :struct} do
      constraints items: [instance_of: __MODULE__]
      transaction? true
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false

      argument :decisions, {:array, ReviewInput},
        allow_nil?: false,
        constraints: [min_length: 1]

      run {Module.concat(["QuickTrain.Tasks.Reviews.QuestionReview"]), []}
    end

    read :read do
      primary? true

      pagination keyset?: true,
                 required?: false,
                 default_limit: 50,
                 max_page_size: 100,
                 stable_sort: [number: :asc, id: :asc]
    end

    create :create_internal do
      accept [
        :origin,
        :verdict,
        :number,
        :request_key,
        :reason,
        :organization_id,
        :project_id,
        :form_version_id,
        :task_id,
        :question_id,
        :question_response_id,
        :requester_id,
        :predecessor_id
      ]

      validate present([:requester_id, :request_key]), where: [attribute_equals(:origin, :human)]
      validate absent([:requester_id, :request_key]), where: [attribute_equals(:origin, :system)]
      validate attribute_equals(:verdict, :accept), where: [attribute_equals(:origin, :system)]
    end
  end

  policies do
    policy action(:read) do
      authorize_if ReadAccess
    end

    policy action([:decide, :review_batch]) do
      authorize_if {OrganizationCapability, capability: "tasks.review"}
    end
  end

  graphql do
    type :review_decision
    derive_filter? false
    derive_sort? false
    relationships [:question_response]
  end

  postgres do
    table "review_decisions"
    repo Repo
    migration_types number: :bigint

    references do
      reference :organization,
        on_delete: :restrict,
        name: "review_decisions_organization_scope_fkey"

      reference :project,
        on_delete: :restrict,
        name: "review_decisions_project_scope_fkey",
        match_with: [organization_id: :organization_id, form_version_id: :form_version_id]

      reference :form_version,
        on_delete: :restrict,
        name: "review_decisions_form_version_scope_fkey"

      reference :task,
        on_delete: :restrict,
        name: "review_decisions_task_scope_fkey",
        match_with: [project_id: :project_id, form_version_id: :form_version_id]

      reference :question,
        on_delete: :restrict,
        name: "review_decisions_question_scope_fkey",
        match_with: [form_version_id: :version_id]

      reference :question_response,
        on_delete: :restrict,
        name: "review_decisions_question_response_scope_fkey",
        match_with: [
          task_id: :task_id,
          project_id: :project_id,
          form_version_id: :form_version_id,
          question_id: :question_id
        ]

      reference :requester, on_delete: :restrict, name: "review_decisions_requester_scope_fkey"

      reference :predecessor,
        on_delete: :restrict,
        name: "review_decisions_predecessor_scope_fkey",
        match_with: [question_response_id: :question_response_id]
    end

    custom_indexes do
      index [:id, :question_response_id], unique: true, name: "review_decisions_scope_0"
    end
  end

  identities do
    identity :decision_number, [:question_response_id, :number]
    identity :request, [:question_response_id, :requester_id, :request_key]
  end
end
