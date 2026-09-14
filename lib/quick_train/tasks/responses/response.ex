defmodule QuickTrain.Tasks.Responses.Response do
  @moduledoc "Scoped collection response evidence."
  use Ash.Resource,
    primary_read_warning?: false,
    otp_app: :quick_train,
    domain: QuickTrain.Tasks,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id

    attribute :state, :atom,
      public?: true,
      allow_nil?: false,
      default: :draft,
      constraints: [one_of: [:draft, :submitted]]

    attribute :revision, :integer,
      public?: true,
      allow_nil?: false,
      default: 0,
      constraints: [min: 0]

    attribute :submitted_at, :utc_datetime_usec, public?: true, allow_nil?: true
    timestamps()
  end

  relationships do
    has_many :outcomes, QuickTrain.Tasks.Responses.QuestionResponse,
      destination_attribute: :response_id,
      public?: true

    belongs_to :organization, QuickTrain.Organizations.Organization,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :project, QuickTrain.Projects.Project, allow_nil?: false, attribute_public?: true

    belongs_to :form_version, QuickTrain.Forms.FormVersion,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :task, QuickTrain.Tasks.Task, allow_nil?: false, attribute_public?: true

    belongs_to :attempt, QuickTrain.Tasks.Attempts.Attempt,
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

    action :submit, :struct do
      transaction? true
      constraints instance_of: QuickTrain.Tasks.Attempts.Attempt
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      argument :attempt_id, :uuid, allow_nil?: false
      run Module.concat(["QuickTrain.Tasks.Responses.ResponseSubmission"])
    end

    action :save_question, :struct do
      transaction? true
      constraints instance_of: __MODULE__
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      argument :attempt_id, :uuid, allow_nil?: false
      argument :question_id, :uuid, allow_nil?: false
      argument :expected_revision, :integer, allow_nil?: false, constraints: [min: 0]
      argument :answer, QuickTrain.Tasks.Responses.Inputs.AnswerInput, allow_nil?: false
      run Module.concat(["QuickTrain.Tasks.Responses.ResponseDraft"])
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
        :state,
        :revision,
        :submitted_at,
        :organization_id,
        :project_id,
        :form_version_id,
        :task_id,
        :attempt_id
      ]
    end

    update :revise do
      accept []
      require_atomic? false
      change Module.concat(["QuickTrain.Tasks.Responses.Changes.DraftEvidence"])
      change increment(:revision)
    end

    update :update_internal do
      change Module.concat(["QuickTrain.Tasks.Responses.Changes.DraftEvidence"])
      require_atomic? false
      accept [:state, :revision, :submitted_at]
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

    policy action([:save_question, :submit]) do
      authorize_if actor_present()
    end

    policy action([:create_internal, :update_internal, :revise]) do
      forbid_if always()
    end
  end

  graphql do
    type :response
    derive_filter? false
    derive_sort? false
    paginate_relationship_with outcomes: :relay
    relationships [:outcomes, :attempt]
  end

  postgres do
    table "responses"
    repo QuickTrain.Repo
    migration_types revision: :bigint

    references do
      reference :organization, on_delete: :restrict, name: "responses_organization_scope_fkey"

      reference :project,
        on_delete: :restrict,
        name: "responses_project_scope_fkey",
        match_with: [organization_id: :organization_id, form_version_id: :form_version_id]

      reference :form_version, on_delete: :restrict, name: "responses_form_version_scope_fkey"

      reference :task,
        on_delete: :restrict,
        name: "responses_task_scope_fkey",
        match_with: [project_id: :project_id, form_version_id: :form_version_id]

      reference :attempt,
        on_delete: :restrict,
        name: "responses_attempt_scope_fkey",
        match_with: [
          task_id: :task_id,
          project_id: :project_id,
          form_version_id: :form_version_id
        ]
    end

    custom_indexes do
      index [:id, :task_id, :project_id, :form_version_id],
        unique: true,
        name: "responses_scope_0"
    end
  end

  identities do
    identity :attempt, [:attempt_id]
  end
end
