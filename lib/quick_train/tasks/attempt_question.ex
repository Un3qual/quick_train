defmodule QuickTrain.Tasks.AttemptQuestion do
  @moduledoc "Scoped collection attempt question evidence."
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
    belongs_to :attempt, QuickTrain.Tasks.Attempt, allow_nil?: false, attribute_public?: true

    belongs_to :question, QuickTrain.Forms.Questions.QuestionDefinition,
      allow_nil?: false,
      attribute_public?: true,
      public?: true
  end

  calculations do
    calculate :skip_allowed,
              :boolean,
              {Module.concat(["QuickTrain.Tasks.OfferedPolicy"]), field: :skip_allowed},
              public?: true

    calculate :reason_required,
              :boolean,
              {Module.concat(["QuickTrain.Tasks.OfferedPolicy"]), field: :reason_required},
              public?: true

    calculate :review_status,
              :atom,
              {Module.concat(["QuickTrain.Tasks.OfferedPolicy"]), field: :review_status},
              public?: true
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
        :organization_id,
        :project_id,
        :form_version_id,
        :task_id,
        :attempt_id,
        :question_id
      ]
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

    policy action([:create_internal]) do
      forbid_if always()
    end
  end

  graphql do
    type :attempt_question
    derive_filter? false
    derive_sort? false
    relationships [:question]
  end

  postgres do
    table "attempt_questions"
    repo QuickTrain.Repo
    migration_defaults id: "fragment(\"gen_random_uuid()\")"

    references do
      reference :organization,
        on_delete: :restrict,
        name: "attempt_questions_organization_scope_fkey"

      reference :project,
        on_delete: :restrict,
        name: "attempt_questions_project_scope_fkey",
        match_with: [organization_id: :organization_id, form_version_id: :form_version_id]

      reference :form_version,
        on_delete: :restrict,
        name: "attempt_questions_form_version_scope_fkey"

      reference :task,
        on_delete: :restrict,
        name: "attempt_questions_task_scope_fkey",
        match_with: [project_id: :project_id, form_version_id: :form_version_id]

      reference :attempt,
        on_delete: :restrict,
        name: "attempt_questions_attempt_scope_fkey",
        match_with: [
          task_id: :task_id,
          project_id: :project_id,
          form_version_id: :form_version_id
        ]

      reference :question,
        on_delete: :restrict,
        name: "attempt_questions_question_scope_fkey",
        match_with: [form_version_id: :version_id]
    end

    custom_indexes do
      index [:id, :attempt_id, :question_id], unique: true, name: "attempt_questions_scope_0"
    end
  end

  identities do
    identity :offered, [:attempt_id, :question_id]
  end
end
