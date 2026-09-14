defmodule QuickTrain.Tasks.Responses.QuestionResponse do
  @moduledoc "Scoped collection question response evidence."
  use Ash.Resource,
    primary_read_warning?: false,
    otp_app: :quick_train,
    domain: QuickTrain.Tasks,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id

    attribute :outcome, :atom,
      public?: true,
      allow_nil?: false,
      constraints: [one_of: [:answered, :skipped]]

    attribute :family, QuickTrain.Forms.Types.AnswerFamily, public?: true, allow_nil?: false

    attribute :text_value, :string,
      public?: true,
      allow_nil?: true,
      constraints: [trim?: false, allow_empty?: true, match: ~r/\A[^\x00]*\z/u]

    attribute :integer_value, :integer,
      public?: true,
      allow_nil?: true,
      constraints: [min: -2_147_483_648, max: 2_147_483_647]

    attribute :decimal_value, :decimal, public?: true, allow_nil?: true
    attribute :boolean_value, :boolean, public?: true, allow_nil?: true

    attribute :reason, :string,
      public?: true,
      allow_nil?: true,
      constraints: [trim?: false, allow_empty?: true]

    attribute :explanation, :string,
      public?: true,
      allow_nil?: true,
      constraints: [trim?: false, allow_empty?: true]

    attribute :skipped_at, :utc_datetime_usec, public?: true, allow_nil?: true
    timestamps()
  end

  relationships do
    has_many :static_options, QuickTrain.Tasks.Responses.StaticOptionAnswer,
      destination_attribute: :question_response_id,
      public?: true

    has_many :input_answers, QuickTrain.Tasks.Responses.TaskInputAnswer,
      destination_attribute: :question_response_id,
      public?: true

    has_many :text_spans, QuickTrain.Tasks.Responses.TextSpan,
      destination_attribute: :question_response_id,
      public?: true

    has_many :review_decisions, QuickTrain.Tasks.Reviews.ReviewDecision,
      destination_attribute: :question_response_id,
      public?: true

    has_one :effective_decision, QuickTrain.Tasks.Reviews.ReviewDecision do
      destination_attribute :question_response_id
      from_many? true
      sort number: :desc
      public? true
    end

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

    belongs_to :question, QuickTrain.Forms.Questions.QuestionDefinition,
      allow_nil?: false,
      attribute_public?: true,
      public?: true
  end

  aggregates do
    first :effective_verdict, :review_decisions, :verdict do
      sort number: :desc
      public? true
    end

    first :effective_decision_number, :review_decisions, :number do
      sort number: :desc
    end
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
        :outcome,
        :family,
        :text_value,
        :integer_value,
        :decimal_value,
        :boolean_value,
        :reason,
        :explanation,
        :skipped_at,
        :organization_id,
        :project_id,
        :form_version_id,
        :task_id,
        :attempt_id,
        :question_id
      ]

      for {field, family} <- [
            {:text_value, :text},
            {:integer_value, :integer},
            {:decimal_value, :decimal},
            {:boolean_value, :boolean}
          ] do
        validate attribute_equals(:outcome, :answered), where: [present(field)]
        validate attribute_equals(:family, family), where: [present(field)]
      end
    end

    destroy :destroy_internal do
      require_atomic? false
      change Module.concat(["QuickTrain.Tasks.Responses.Changes.DraftEvidence"])
      change cascade_destroy(:static_options, action: :destroy_internal, after_action?: false)
      change cascade_destroy(:input_answers, action: :destroy_internal, after_action?: false)
      change cascade_destroy(:text_spans, action: :destroy_internal, after_action?: false)
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
    type :question_response
    derive_filter? false
    derive_sort? false

    paginate_relationship_with static_options: :relay,
                               input_answers: :relay,
                               text_spans: :relay,
                               review_decisions: :relay

    relationships [
      :attempt,
      :question,
      :static_options,
      :input_answers,
      :text_spans,
      :review_decisions,
      :effective_decision
    ]
  end

  postgres do
    table "question_responses"
    repo QuickTrain.Repo
    migration_types integer_value: :bigint

    references do
      reference :organization,
        on_delete: :restrict,
        name: "question_responses_organization_scope_fkey"

      reference :project,
        on_delete: :restrict,
        name: "question_responses_project_scope_fkey",
        match_with: [organization_id: :organization_id, form_version_id: :form_version_id]

      reference :form_version,
        on_delete: :restrict,
        name: "question_responses_form_version_scope_fkey"

      reference :task,
        on_delete: :restrict,
        name: "question_responses_task_scope_fkey",
        match_with: [project_id: :project_id, form_version_id: :form_version_id]

      reference :attempt,
        on_delete: :restrict,
        name: "question_responses_attempt_scope_fkey",
        match_with: [
          task_id: :task_id,
          project_id: :project_id,
          form_version_id: :form_version_id
        ]

      reference :question,
        on_delete: :restrict,
        name: "question_responses_question_scope_fkey",
        match_with: [form_version_id: :version_id]
    end

    custom_indexes do
      index [:id, :task_id, :project_id, :form_version_id, :question_id],
        unique: true,
        name: "question_responses_scope_0"
    end
  end

  identities do
    identity :attempt_question, [:attempt_id, :question_id]
  end
end
