defmodule QuickTrain.Tasks.Reviews.ReviewDecision do
  @moduledoc "Scoped collection review decision evidence."
  use Ash.Resource,
    primary_read_warning?: false,
    otp_app: :quick_train,
    domain: QuickTrain.Tasks,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

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
      public?: true,
      attribute_public?: true

    belongs_to :requester, QuickTrain.Accounts.User, allow_nil?: true, attribute_public?: true

    belongs_to :predecessor, QuickTrain.Tasks.Reviews.ReviewDecision,
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

      argument :decisions, {:array, QuickTrain.Tasks.Reviews.QuestionReview.Input},
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
                   stable_sort: [number: :asc, id: :asc]
      end

      read get_action do
        get? true
        argument :organization_id, :uuid, allow_nil?: false
        argument :project_id, :uuid, allow_nil?: false
        argument :id, :uuid, allow_nil?: false

        filter expr(
                 id == ^arg(:id) and organization_id == ^arg(:organization_id) and
                   project_id == ^arg(:project_id)
               )

        prepare {Module.concat(["QuickTrain.Tasks.Access.ReadAccess.Prepare"]), mode: mode}
      end
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
    end
  end

  policies do
    policy action(:read) do
      authorize_if Module.concat(["QuickTrain.Tasks.Access.ReadAccess"])
    end

    policy action([:list_audit, :list_accepted, :get_audit, :get_accepted]) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "tasks.results.read"}
    end

    policy action([:decide, :review_batch]) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "tasks.review"}
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
    repo QuickTrain.Repo
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

    check_constraints do
      check_constraint :id, "review_decisions_origin",
        check:
          "(origin = 'human' AND requester_id IS NOT NULL AND request_key IS NOT NULL) OR (origin = 'system' AND requester_id IS NULL AND request_key IS NULL AND verdict = 'accept')"
    end
  end

  identities do
    identity :decision_number, [:question_response_id, :number]
    identity :request, [:question_response_id, :requester_id, :request_key]
  end
end
