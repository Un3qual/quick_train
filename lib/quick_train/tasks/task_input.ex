defmodule QuickTrain.Tasks.TaskInput do
  @moduledoc "Scoped collection task input evidence."
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
    has_many :requirements, QuickTrain.Forms.Inputs.InputFieldRequirement,
      source_attribute: :input_slot_id,
      destination_attribute: :input_slot_id,
      public?: true

    belongs_to :organization, QuickTrain.Organizations.Organization,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :project, QuickTrain.Projects.Project, allow_nil?: false, attribute_public?: true

    belongs_to :form_version, QuickTrain.Forms.FormVersion,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :task, QuickTrain.Tasks.Task, allow_nil?: false, attribute_public?: true

    belongs_to :project_item, QuickTrain.Projects.ProjectItem,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :revision, QuickTrain.Datasets.DatasetItemRevision,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :input_slot, QuickTrain.Forms.Inputs.InputSlotDefinition,
      allow_nil?: false,
      attribute_public?: true,
      public?: true
  end

  actions do
    action :source_download, QuickTrain.Assets.AssetAccessResult do
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      argument :task_input_id, :uuid, allow_nil?: false
      argument :requirement_id, :uuid, allow_nil?: false
      argument :attempt_id, :uuid
      run Module.concat(["QuickTrain.Tasks.Access.ReadActions"])
    end

    action :bound_value, QuickTrain.Tasks.Access.BoundValue do
      transaction? true
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      argument :task_input_id, :uuid, allow_nil?: false
      argument :requirement_id, :uuid, allow_nil?: false
      argument :attempt_id, :uuid
      run Module.concat(["QuickTrain.Tasks.Access.ReadActions"])
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
        :project_item_id,
        :revision_id,
        :input_slot_id
      ]
    end
  end

  policies do
    policy action([:bound_value, :source_download]) do
      authorize_if actor_present()
    end

    policy action(:read) do
      authorize_if Module.concat(["QuickTrain.Tasks.Access.ReadAccess"])
    end

    policy action([:create_internal]) do
      forbid_if always()
    end
  end

  graphql do
    type :task_input
    derive_filter? false
    derive_sort? false
    paginate_relationship_with requirements: :relay
    relationships [:input_slot, :requirements]
  end

  postgres do
    table "task_inputs"
    repo QuickTrain.Repo

    references do
      reference :organization, on_delete: :restrict, name: "task_inputs_organization_scope_fkey"

      reference :project,
        on_delete: :restrict,
        name: "task_inputs_project_scope_fkey",
        match_with: [organization_id: :organization_id, form_version_id: :form_version_id]

      reference :form_version, on_delete: :restrict, name: "task_inputs_form_version_scope_fkey"

      reference :task,
        on_delete: :restrict,
        name: "task_inputs_task_scope_fkey",
        match_with: [project_id: :project_id, form_version_id: :form_version_id]

      reference :project_item,
        on_delete: :restrict,
        name: "task_inputs_project_item_scope_fkey",
        match_with: [project_id: :project_id, revision_id: :revision_id]

      reference :revision, on_delete: :restrict, name: "task_inputs_revision_scope_fkey"

      reference :input_slot,
        on_delete: :restrict,
        name: "task_inputs_input_slot_scope_fkey",
        match_with: [form_version_id: :version_id]
    end

    custom_indexes do
      index [:id, :task_id, :project_id, :form_version_id],
        unique: true,
        name: "task_inputs_scope_0"

      index [:id, :task_id, :input_slot_id], unique: true, name: "task_inputs_scope_1"
    end
  end

  identities do
    identity :task_item, [:task_id, :project_item_id]
  end
end
