defmodule QuickTrain.Tasks.Context.ProjectInputBinding do
  @moduledoc false
  use QuickTrain.Tasks.Context.Resource,
    source: QuickTrain.Projects.ProjectInputBinding,
    fields: [
      :id,
      :project_id,
      :schema_version_id,
      :root_record_type_id,
      :form_version_id,
      :requirement_id,
      :field_definition_id,
      :inserted_at,
      :updated_at
    ],
    definition?: false,
    sort: [inserted_at: :asc, id: :asc]

  relationships do
    belongs_to :project, QuickTrain.Projects.Project, define_attribute?: false

    has_many :issued_inputs, QuickTrain.Tasks.TaskInput,
      source_attribute: :project_id,
      destination_attribute: :project_id

    belongs_to :requirement, QuickTrain.Tasks.Context.InputFieldRequirement,
      define_attribute?: false,
      public?: true

    belongs_to :field_definition, QuickTrain.Tasks.Context.DatasetFieldDefinition,
      define_attribute?: false,
      public?: true
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
  end

  policies do
    policy action([:list_result_bindings, :get_result_binding]) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "tasks.results.read"}
    end
  end

  graphql do
    type :task_project_input_binding
    derive_filter? false
    derive_sort? false
    relationships [:requirement, :field_definition]
  end
end
