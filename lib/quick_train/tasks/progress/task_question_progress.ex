defmodule QuickTrain.Tasks.Progress.TaskQuestionProgress do
  @moduledoc "Scoped collection task question progress evidence."
  use Ash.Resource,
    primary_read_warning?: false,
    otp_app: :quick_train,
    domain: QuickTrain.Tasks,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id

    attribute :target, :integer,
      public?: true,
      allow_nil?: false,
      constraints: [min: 1, max: 2_147_483_647]

    attribute :failure_threshold, :integer,
      public?: true,
      allow_nil?: false,
      constraints: [min: 1, max: 2_147_483_647]

    attribute :accepted, :integer,
      public?: true,
      allow_nil?: false,
      default: 0,
      constraints: [min: 0]

    attribute :pending, :integer,
      public?: true,
      allow_nil?: false,
      default: 0,
      constraints: [min: 0]

    attribute :skipped, :integer,
      public?: true,
      allow_nil?: false,
      default: 0,
      constraints: [min: 0]

    attribute :rejected, :integer,
      public?: true,
      allow_nil?: false,
      default: 0,
      constraints: [min: 0]

    attribute :live, :integer, public?: true, allow_nil?: false, default: 0, constraints: [min: 0]

    attribute :failures, :integer,
      public?: true,
      allow_nil?: false,
      default: 0,
      constraints: [min: 0]

    attribute :attention, :boolean, public?: true, allow_nil?: false, default: false
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
      accept [
        :target,
        :failure_threshold,
        :accepted,
        :pending,
        :skipped,
        :rejected,
        :live,
        :failures,
        :attention,
        :organization_id,
        :project_id,
        :form_version_id,
        :task_id,
        :question_id
      ]
    end

    update :update_internal do
      accept [:accepted, :pending, :skipped, :rejected, :live, :failures, :attention]
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

    policy action([:create_internal, :update_internal]) do
      forbid_if always()
    end
  end

  graphql do
    type :task_question_progress

    attribute_types accepted: :string,
                    pending: :string,
                    skipped: :string,
                    rejected: :string,
                    live: :string,
                    failures: :string

    derive_filter? false
    derive_sort? false
    relationships []
  end

  postgres do
    table "task_question_progress"
    repo QuickTrain.Repo

    migration_types target: :bigint,
                    failure_threshold: :bigint,
                    accepted: :bigint,
                    pending: :bigint,
                    skipped: :bigint,
                    rejected: :bigint,
                    live: :bigint,
                    failures: :bigint

    references do
      reference :organization,
        on_delete: :restrict,
        name: "task_question_progress_organization_scope_fkey"

      reference :project,
        on_delete: :restrict,
        name: "task_question_progress_project_scope_fkey",
        match_with: [organization_id: :organization_id, form_version_id: :form_version_id]

      reference :form_version,
        on_delete: :restrict,
        name: "task_question_progress_form_version_scope_fkey"

      reference :task,
        on_delete: :restrict,
        name: "task_question_progress_task_scope_fkey",
        match_with: [project_id: :project_id, form_version_id: :form_version_id]

      reference :question,
        on_delete: :restrict,
        name: "task_question_progress_question_scope_fkey",
        match_with: [form_version_id: :version_id]
    end

    check_constraints do
      check_constraint :id, "task_question_progress_counts",
        check:
          "accepted >= 0 AND pending >= 0 AND skipped >= 0 AND rejected >= 0 AND live >= 0 AND failures >= 0"
    end
  end

  identities do
    identity :task_question, [:task_id, :question_id]
  end
end
