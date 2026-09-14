defmodule QuickTrain.Projects.ProjectInputBinding do
  @moduledoc "Organization-scoped project configuration."
  use Ash.Resource,
    primary_read_warning?: false,
    otp_app: :quick_train,
    domain: QuickTrain.Projects,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshGraphql.Resource],
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      generated?: true,
      public?: true,
      writable?: false

    timestamps()
  end

  relationships do
    has_many :issued_inputs, QuickTrain.Tasks.TaskInput,
      source_attribute: :project_id,
      destination_attribute: :project_id

    belongs_to :project, QuickTrain.Projects.Project, allow_nil?: false, attribute_public?: true

    belongs_to :schema_version, QuickTrain.Datasets.DatasetSchemaVersion,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :root_record_type, QuickTrain.Datasets.DatasetRecordType,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :form_version, QuickTrain.Forms.FormVersion,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :requirement, QuickTrain.Forms.Inputs.InputFieldRequirement,
      public?: true,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :field_definition, QuickTrain.Datasets.DatasetFieldDefinition,
      public?: true,
      allow_nil?: false,
      attribute_public?: true
  end

  actions do
    read :list_result_bindings do
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false

      filter expr(
               project_id == ^arg(:project_id) and
                 project.organization_id == ^arg(:organization_id)
             )

      filter expr(exists(issued_inputs, input_slot_id == parent(requirement.input_slot_id)))
      prepare build(sort: [inserted_at: :asc, id: :asc])

      pagination keyset?: true,
                 required?: true,
                 default_limit: 50,
                 max_page_size: 100,
                 stable_sort: [inserted_at: :asc, id: :asc]
    end

    read :get_result_binding do
      get? true
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id))
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false

      filter expr(
               project_id == ^arg(:project_id) and
                 project.organization_id == ^arg(:organization_id)
             )

      filter expr(exists(issued_inputs, input_slot_id == parent(requirement.input_slot_id)))
    end

    read :read do
      primary? true

      prepare build(sort: [inserted_at: :asc, id: :asc])

      pagination keyset?: true,
                 required?: false,
                 default_limit: 50,
                 max_page_size: 100,
                 stable_sort: [inserted_at: :asc, id: :asc]
    end

    read :list_scoped do
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false

      filter expr(
               project_id == ^arg(:project_id) and
                 project.organization_id == ^arg(:organization_id)
             )

      prepare build(sort: [inserted_at: :asc, id: :asc])

      pagination keyset?: true,
                 required?: true,
                 default_limit: 50,
                 max_page_size: 100,
                 stable_sort: [inserted_at: :asc, id: :asc]
    end

    create :create_internal do
      accept [
        :project_id,
        :schema_version_id,
        :root_record_type_id,
        :form_version_id,
        :requirement_id,
        :field_definition_id
      ]
    end

    update :update_internal do
      accept [:field_definition_id]
    end

    destroy :destroy_internal
  end

  policies do
    policy action([:list_result_bindings, :get_result_binding]) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "tasks.results.read"}
    end

    policy action(:read) do
      forbid_unless actor_attribute_equals(:status, "active")
      authorize_if relates_to_actor_via([:project, :reader_role_assignments, :user])
    end

    policy action(:read) do
      authorize_if accessing_from(Module.concat(["QuickTrain.Projects.Project"]), :bindings)
    end

    policy action(:list_scoped) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "projects.read"}
    end
  end

  graphql do
    type :project_input_binding
    derive_filter? false
    derive_sort? false
    relationships [:requirement, :field_definition]
  end

  postgres do
    table "project_input_bindings"
    repo QuickTrain.Repo
    migration_defaults id: "fragment(\"gen_random_uuid()\")"

    references do
      reference :project,
        on_delete: :restrict,
        match_with: [
          schema_version_id: :schema_version_id,
          root_record_type_id: :root_record_type_id,
          form_version_id: :form_version_id
        ]

      reference :schema_version, on_delete: :restrict

      reference :root_record_type,
        on_delete: :restrict,
        match_with: [schema_version_id: :schema_version_id]

      reference :form_version, on_delete: :restrict
      reference :requirement, on_delete: :restrict, match_with: [form_version_id: :version_id]

      reference :field_definition,
        on_delete: :restrict,
        match_with: [root_record_type_id: :record_type_id]
    end

    custom_indexes do
      index [:id, :project_id, :field_definition_id],
        unique: true,
        name: "project_input_bindings_id_project_field_index"

      index [:id, :project_id], unique: true
    end
  end

  identities do
    identity :project_requirement, [:project_id, :requirement_id]
  end
end
