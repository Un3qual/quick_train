defmodule QuickTrain.Tasks.Responses.StaticOptionAnswer do
  @moduledoc "Scoped collection static option answer evidence."
  use Ash.Resource,
    primary_read_warning?: false,
    otp_app: :quick_train,
    domain: QuickTrain.Tasks,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias QuickTrain.Forms.FormVersion
  alias QuickTrain.Forms.Questions.{QuestionDefinition, QuestionOption}
  alias QuickTrain.Organizations.Organization
  alias QuickTrain.Projects.Project
  alias QuickTrain.Repo
  alias QuickTrain.Tasks.Access.ReadAccess
  alias QuickTrain.Tasks.Responses.QuestionResponse
  alias QuickTrain.Tasks.Task

  attributes do
    uuid_primary_key :id

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

    belongs_to :option, QuestionOption,
      allow_nil?: false,
      attribute_public?: true,
      public?: true
  end

  actions do
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
      change Module.concat(["QuickTrain.Tasks.Responses.Changes.DraftEvidence"])

      accept [
        :organization_id,
        :project_id,
        :form_version_id,
        :task_id,
        :question_id,
        :question_response_id,
        :option_id
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
    type :static_option_answer
    derive_filter? false
    derive_sort? false
    relationships [:option]
  end

  postgres do
    table "static_option_answers"
    repo Repo

    references do
      reference :organization,
        on_delete: :restrict,
        name: "static_option_answers_organization_scope_fkey"

      reference :project,
        on_delete: :restrict,
        name: "static_option_answers_project_scope_fkey",
        match_with: [organization_id: :organization_id, form_version_id: :form_version_id]

      reference :form_version,
        on_delete: :restrict,
        name: "static_option_answers_form_version_scope_fkey"

      reference :task,
        on_delete: :restrict,
        name: "static_option_answers_task_scope_fkey",
        match_with: [project_id: :project_id, form_version_id: :form_version_id]

      reference :question,
        on_delete: :restrict,
        name: "static_option_answers_question_scope_fkey",
        match_with: [form_version_id: :version_id]

      reference :question_response,
        on_delete: :restrict,
        name: "static_option_answers_question_response_scope_fkey",
        match_with: [
          task_id: :task_id,
          project_id: :project_id,
          form_version_id: :form_version_id,
          question_id: :question_id
        ]

      reference :option,
        on_delete: :restrict,
        name: "static_option_answers_option_scope_fkey",
        match_with: [question_id: :question_id, form_version_id: :version_id]
    end
  end

  identities do
    identity :option, [:question_response_id, :option_id]
  end
end
