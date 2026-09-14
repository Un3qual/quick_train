defmodule QuickTrain.Tasks.Attempts.AttemptInputPresentation do
  @moduledoc "Scoped collection attempt input presentation evidence."
  use Ash.Resource,
    primary_read_warning?: false,
    otp_app: :quick_train,
    domain: QuickTrain.Tasks,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id

    attribute :position, :integer, public?: true, allow_nil?: false, constraints: [min: 0]
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

    belongs_to :attempt, QuickTrain.Tasks.Attempts.Attempt,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :task_input, QuickTrain.Tasks.TaskInput,
      allow_nil?: false,
      attribute_public?: true,
      public?: true

    belongs_to :input_slot, QuickTrain.Tasks.Context.InputSlotDefinition,
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

      prepare build(sort: [position: :asc, id: :asc])

      pagination keyset?: true,
                 required?: false,
                 default_limit: 50,
                 max_page_size: 100,
                 stable_sort: [position: :asc, id: :asc]
    end

    create :create_internal do
      accept [
        :position,
        :organization_id,
        :project_id,
        :form_version_id,
        :task_id,
        :attempt_id,
        :task_input_id,
        :input_slot_id
      ]
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

    policy action([:create_internal]) do
      forbid_if always()
    end
  end

  graphql do
    type :attempt_input_presentation
    derive_filter? false
    derive_sort? false
    relationships [:task_input, :input_slot]
  end

  postgres do
    table "attempt_input_presentations"
    repo QuickTrain.Repo
    migration_types position: :bigint

    references do
      reference :organization,
        on_delete: :restrict,
        name: "attempt_input_presentations_organization_scope_fkey"

      reference :project,
        on_delete: :restrict,
        name: "attempt_input_presentations_project_scope_fkey",
        match_with: [organization_id: :organization_id, form_version_id: :form_version_id]

      reference :form_version,
        on_delete: :restrict,
        name: "attempt_input_presentations_form_version_scope_fkey"

      reference :task,
        on_delete: :restrict,
        name: "attempt_input_presentations_task_scope_fkey",
        match_with: [project_id: :project_id, form_version_id: :form_version_id]

      reference :attempt,
        on_delete: :restrict,
        name: "attempt_input_presentations_attempt_scope_fkey",
        match_with: [
          task_id: :task_id,
          project_id: :project_id,
          form_version_id: :form_version_id
        ]

      reference :task_input,
        on_delete: :restrict,
        name: "attempt_input_presentations_task_input_scope_fkey",
        match_with: [task_id: :task_id, input_slot_id: :input_slot_id]

      reference :input_slot,
        on_delete: :restrict,
        name: "attempt_input_presentations_input_slot_scope_fkey",
        match_with: [form_version_id: :version_id]
    end
  end

  identities do
    identity :input, [:attempt_id, :task_input_id]
    identity :display_position, [:attempt_id, :input_slot_id, :position]
  end
end
