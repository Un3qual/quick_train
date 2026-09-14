defmodule QuickTrain.Tasks.TextSpan do
  @moduledoc "Scoped collection text span evidence."
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

    attribute :start, :integer, public?: true, allow_nil?: false, constraints: [min: 0]
    attribute :end, :integer, public?: true, allow_nil?: false, constraints: [min: 1]
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

    belongs_to :question_response, QuickTrain.Tasks.QuestionResponse,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :task_input, QuickTrain.Tasks.TaskInput,
      allow_nil?: false,
      attribute_public?: true,
      public?: true

    belongs_to :source_value, QuickTrain.Datasets.DatasetValue,
      allow_nil?: false,
      attribute_public?: true,
      public?: true

    belongs_to :label, QuickTrain.Forms.Labels.Label,
      allow_nil?: false,
      attribute_public?: true,
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
      change Module.concat(["QuickTrain.Tasks.Changes.DraftEvidence"])

      accept [
        :start,
        :end,
        :organization_id,
        :project_id,
        :form_version_id,
        :task_id,
        :question_id,
        :question_response_id,
        :task_input_id,
        :source_value_id,
        :label_id
      ]
    end

    destroy :destroy_internal do
      change Module.concat(["QuickTrain.Tasks.Changes.DraftEvidence"])
      require_atomic? false
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

    policy action([:create_internal, :destroy_internal]) do
      forbid_if always()
    end
  end

  graphql do
    type :text_span
    derive_filter? false
    derive_sort? false
    relationships [:task_input, :source_value, :label]
  end

  postgres do
    table "text_spans"
    repo QuickTrain.Repo
    migration_defaults id: "fragment(\"gen_random_uuid()\")"
    migration_types start: :bigint, end: :bigint

    references do
      reference :organization, on_delete: :restrict, name: "text_spans_organization_scope_fkey"

      reference :project,
        on_delete: :restrict,
        name: "text_spans_project_scope_fkey",
        match_with: [organization_id: :organization_id, form_version_id: :form_version_id]

      reference :form_version, on_delete: :restrict, name: "text_spans_form_version_scope_fkey"

      reference :task,
        on_delete: :restrict,
        name: "text_spans_task_scope_fkey",
        match_with: [project_id: :project_id, form_version_id: :form_version_id]

      reference :question,
        on_delete: :restrict,
        name: "text_spans_question_scope_fkey",
        match_with: [form_version_id: :version_id]

      reference :question_response,
        on_delete: :restrict,
        name: "text_spans_question_response_scope_fkey",
        match_with: [
          task_id: :task_id,
          project_id: :project_id,
          form_version_id: :form_version_id,
          question_id: :question_id
        ]

      reference :task_input,
        on_delete: :restrict,
        name: "text_spans_task_input_scope_fkey",
        match_with: [
          task_id: :task_id,
          project_id: :project_id,
          form_version_id: :form_version_id
        ]

      reference :source_value, on_delete: :restrict, name: "text_spans_source_value_scope_fkey"

      reference :label,
        on_delete: :restrict,
        name: "text_spans_label_scope_fkey",
        match_with: [form_version_id: :version_id]
    end

    check_constraints do
      check_constraint :id, "text_spans_range", check: "\"start\" >= 0 AND \"end\" > \"start\""
    end
  end

  identities do
    identity :span, [
      :question_response_id,
      :task_input_id,
      :source_value_id,
      :label_id,
      :start,
      :end
    ]
  end
end
