defmodule QuickTrain.Tasks.Responses.StaticOptionAnswer do
  @moduledoc "Scoped collection static option answer evidence."
  use Ash.Resource,
    primary_read_warning?: false,
    otp_app: :quick_train,
    domain: QuickTrain.Tasks,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id

    timestamps()
  end

  relationships do
    belongs_to :organization, QuickTrain.Organizations.Organization,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :project, QuickTrain.Projects.Project, allow_nil?: false, attribute_public?: true

    belongs_to :form_version, QuickTrain.Forms.FormVersion,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :task, QuickTrain.Tasks.Task, allow_nil?: false, attribute_public?: true

    belongs_to :question, QuickTrain.Forms.Questions.QuestionDefinition,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :question_response, QuickTrain.Tasks.Responses.QuestionResponse,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :option, QuickTrain.Tasks.Context.QuestionOption,
      allow_nil?: false,
      attribute_public?: true,
      public?: true
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
        prepare {Module.concat(["QuickTrain.Tasks.Access.ReadAccess.Prepare"]), mode: mode}

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
        prepare {Module.concat(["QuickTrain.Tasks.Access.ReadAccess.Prepare"]), mode: mode}
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
      authorize_if Module.concat(["QuickTrain.Tasks.Access.ReadAccess"])
    end

    policy action([:list_audit, :get_audit, :list_accepted, :get_accepted]) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "tasks.results.read"}
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
    repo QuickTrain.Repo

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
