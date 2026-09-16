defmodule QuickTrain.Tasks.Responses.TaskInputAnswer do
  @moduledoc "Scoped collection task input answer evidence."
  use Ash.Resource,
    primary_read_warning?: false,
    otp_app: :quick_train,
    domain: QuickTrain.Tasks,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias QuickTrain.Forms.FormVersion
  alias QuickTrain.Forms.Questions.QuestionDefinition
  alias QuickTrain.Organizations.Organization
  alias QuickTrain.Projects.Project
  alias QuickTrain.Repo
  alias QuickTrain.Tasks.Access.ReadAccess
  alias QuickTrain.Tasks.Responses.QuestionResponse
  alias QuickTrain.Tasks.{Task, TaskInput}

  attributes do
    uuid_primary_key :id

    attribute :position, :integer, public?: true, allow_nil?: true, constraints: [min: 0]
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
      attribute_public?: true

    belongs_to :task_input, TaskInput,
      allow_nil?: false,
      attribute_public?: true,
      public?: true
  end

  actions do
    read :read do
      primary? true

      prepare build(sort: [position: :asc, id: :asc])

      pagination keyset?: true,
                 required?: false,
                 default_limit: 50,
                 max_page_size: 100,
                 stable_sort: [position: :asc, id: :asc]
    end

    create :create_internal do
      change Module.concat(["QuickTrain.Tasks.Responses.Changes.DraftEvidence"])

      accept [
        :position,
        :organization_id,
        :project_id,
        :form_version_id,
        :task_id,
        :question_id,
        :question_response_id,
        :task_input_id
      ]
    end

    destroy :destroy_internal do
      change Module.concat(["QuickTrain.Tasks.Responses.Changes.DraftEvidence"])
      require_atomic? false
    end
  end

  policies do
    policy action(:read) do
      authorize_if ReadAccess
    end

    policy action([:create_internal, :destroy_internal]) do
      forbid_if always()
    end
  end

  graphql do
    type :task_input_answer
    derive_filter? false
    derive_sort? false
    relationships [:task_input]
  end

  postgres do
    table "task_input_answers"
    repo Repo
    migration_types position: :bigint

    references do
      reference :organization,
        on_delete: :restrict,
        name: "task_input_answers_organization_scope_fkey"

      reference :project,
        on_delete: :restrict,
        name: "task_input_answers_project_scope_fkey",
        match_with: [organization_id: :organization_id, form_version_id: :form_version_id]

      reference :form_version,
        on_delete: :restrict,
        name: "task_input_answers_form_version_scope_fkey"

      reference :task,
        on_delete: :restrict,
        name: "task_input_answers_task_scope_fkey",
        match_with: [project_id: :project_id, form_version_id: :form_version_id]

      reference :question,
        on_delete: :restrict,
        name: "task_input_answers_question_scope_fkey",
        match_with: [form_version_id: :version_id]

      reference :question_response,
        on_delete: :restrict,
        name: "task_input_answers_question_response_scope_fkey",
        match_with: [
          task_id: :task_id,
          project_id: :project_id,
          form_version_id: :form_version_id,
          question_id: :question_id
        ]

      reference :task_input,
        on_delete: :restrict,
        name: "task_input_answers_task_input_scope_fkey",
        match_with: [
          task_id: :task_id,
          project_id: :project_id,
          form_version_id: :form_version_id
        ]
    end
  end

  identities do
    identity :input, [:question_response_id, :task_input_id]
    identity :rank, [:question_response_id, :position]
  end
end
