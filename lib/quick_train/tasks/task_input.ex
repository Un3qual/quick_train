defmodule QuickTrain.Tasks.TaskInput do
  @moduledoc "Scoped collection task input evidence."
  use Ash.Resource,
    primary_read_warning?: false,
    otp_app: :quick_train,
    domain: QuickTrain.Tasks,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias QuickTrain.Assets.AssetAccessResult
  alias QuickTrain.Datasets.{Dataset, DatasetItem, DatasetItemRevision, DatasetSchemaVersion}
  alias QuickTrain.Forms.FormVersion
  alias QuickTrain.Forms.Inputs.{InputFieldRequirement, InputSlotDefinition}
  alias QuickTrain.Organizations.Organization
  alias QuickTrain.Projects.Project
  alias QuickTrain.Repo
  alias QuickTrain.Tasks.Access.BoundValue
  alias QuickTrain.Tasks.Access.ReadAccess
  alias QuickTrain.Tasks.Task

  attributes do
    uuid_primary_key :id

    attribute :position, :integer,
      public?: true,
      allow_nil?: false,
      constraints: [min: 0, max: 2_147_483_647]

    timestamps()
  end

  relationships do
    has_many :requirements, InputFieldRequirement,
      source_attribute: :input_slot_id,
      destination_attribute: :input_slot_id,
      public?: true

    belongs_to :organization, Organization,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :project, Project, allow_nil?: false, attribute_public?: true

    belongs_to :form_version, FormVersion,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :task, Task, allow_nil?: false, attribute_public?: true

    belongs_to :dataset, Dataset, allow_nil?: false, attribute_public?: true
    belongs_to :schema_version, DatasetSchemaVersion, allow_nil?: false, attribute_public?: true
    belongs_to :item, DatasetItem, allow_nil?: false, attribute_public?: true

    belongs_to :revision, DatasetItemRevision,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :input_slot, InputSlotDefinition,
      allow_nil?: false,
      attribute_public?: true,
      public?: true
  end

  actions do
    action :source_download, AssetAccessResult do
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      argument :task_input_id, :uuid, allow_nil?: false
      argument :requirement_id, :uuid, allow_nil?: false
      argument :attempt_id, :uuid
      run Module.concat(["QuickTrain.Tasks.Access.ReadActions"])
    end

    action :bound_value, BoundValue do
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
        :position,
        :dataset_id,
        :schema_version_id,
        :item_id,
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
      authorize_if ReadAccess
      authorize_if relates_to_actor_via([:project, :reader_role_assignments, :user])
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
    repo Repo

    references do
      reference :organization, on_delete: :restrict, name: "task_inputs_organization_scope_fkey"

      reference :project,
        on_delete: :restrict,
        name: "task_inputs_project_scope_fkey",
        match_with: [organization_id: :organization_id, form_version_id: :form_version_id]

      reference :form_version, on_delete: :restrict, name: "task_inputs_form_version_scope_fkey"

      reference :task,
        on_delete: :delete,
        name: "task_inputs_task_scope_fkey",
        match_with: [project_id: :project_id, form_version_id: :form_version_id]

      reference :dataset, on_delete: :restrict
      reference :schema_version, on_delete: :restrict, match_with: [dataset_id: :dataset_id]
      reference :item, on_delete: :restrict

      reference :revision,
        on_delete: :restrict,
        match_with: [
          item_id: :item_id,
          dataset_id: :dataset_id,
          schema_version_id: :schema_version_id
        ]

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
    identity :task_item, [:task_id, :item_id]
    identity :slot_position, [:task_id, :input_slot_id, :position]
  end
end
