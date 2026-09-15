defmodule QuickTrain.Tasks.Exports.ExportSelection do
  @moduledoc "Typed immutable evidence membership in one sealed export snapshot."
  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Tasks,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias QuickTrain.Forms.FormVersion
  alias QuickTrain.Forms.Questions.QuestionDefinition
  alias QuickTrain.Organizations.Organization
  alias QuickTrain.Projects.Project
  alias QuickTrain.Repo
  alias QuickTrain.Tasks.Exports.ResultExport
  alias QuickTrain.Tasks.Responses.QuestionResponse
  alias QuickTrain.Tasks.Reviews.ReviewDecision
  alias QuickTrain.Tasks.Task

  attributes do
    uuid_primary_key :id, public?: false
  end

  relationships do
    belongs_to :export, ResultExport, allow_nil?: false
    belongs_to :organization, Organization, allow_nil?: false
    belongs_to :project, Project, allow_nil?: false
    belongs_to :form_version, FormVersion, allow_nil?: false
    belongs_to :task, Task, allow_nil?: false
    belongs_to :question, QuestionDefinition, allow_nil?: false
    belongs_to :question_response, QuestionResponse, allow_nil?: false
    belongs_to :decision, ReviewDecision
  end

  actions do
    read :read do
      primary? true

      pagination keyset?: true,
                 required?: false,
                 default_limit: 100,
                 max_page_size: 100,
                 stable_sort: [id: :asc]
    end

    create :create_internal do
      accept [
        :export_id,
        :organization_id,
        :project_id,
        :form_version_id,
        :task_id,
        :question_id,
        :question_response_id,
        :decision_id
      ]
    end
  end

  policies do
    policy always() do
      forbid_if always()
    end
  end

  postgres do
    table "export_selections"
    repo Repo

    references do
      reference :export,
        on_delete: :restrict,
        match_with: [
          organization_id: :organization_id,
          project_id: :project_id,
          form_version_id: :form_version_id
        ]

      reference :organization, on_delete: :restrict

      reference :project,
        on_delete: :restrict,
        match_with: [organization_id: :organization_id, form_version_id: :form_version_id]

      reference :form_version, on_delete: :restrict

      reference :task,
        on_delete: :restrict,
        match_with: [project_id: :project_id, form_version_id: :form_version_id]

      reference :question, on_delete: :restrict, match_with: [form_version_id: :version_id]

      reference :question_response,
        on_delete: :restrict,
        match_with: [
          task_id: :task_id,
          project_id: :project_id,
          form_version_id: :form_version_id,
          question_id: :question_id
        ]

      reference :decision,
        on_delete: :restrict,
        match_with: [question_response_id: :question_response_id]
    end
  end

  identities do
    identity :membership, [:export_id, :question_response_id]
  end
end
