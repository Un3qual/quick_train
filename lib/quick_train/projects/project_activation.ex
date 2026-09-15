defmodule QuickTrain.Projects.ProjectActivation do
  @moduledoc false
  alias QuickTrain.Projects.{
    Error,
    ExplicitGroup,
    GroupIdentity,
    ProjectInputBinding,
    ProjectItem,
    ProjectSlotPolicy
  }

  alias QuickTrain.Datasets.{
    DatasetFieldDefinition,
    DatasetSchemaVersion,
    DatasetValue
  }

  alias QuickTrain.Forms.FormVersion
  alias QuickTrain.Forms.Inputs.{InputFieldRequirement, InputSlotDefinition}
  alias QuickTrain.Forms.Questions.QuestionDefinition
  require Ash.Query

  def rows(resource, filter) do
    resource |> Ash.Query.filter(^filter) |> Ash.stream!(authorize?: false, batch_size: 100)
  end

  def definition!(resource, project, id) do
    record =
      resource
      |> Ash.Query.filter(id == ^id and version_id == ^project.form_version_id)
      |> Ash.read_one!(authorize?: false)

    if is_nil(record), do: Error.reject!(:invalid_project_configuration)
    record
  end

  def validate_binding!(project, requirement_id, field_id) do
    requirement = definition!(InputFieldRequirement, project, requirement_id)

    field =
      DatasetFieldDefinition
      |> Ash.Query.filter(id == ^field_id and record_type_id == ^project.root_record_type_id)
      |> Ash.read_one!(authorize?: false)

    compatible_binding!(project, requirement, field)
  end

  defp compatible_binding!(project, requirement, field) do
    unless field && field.record_type_id == project.root_record_type_id &&
             field.value_family == requirement.value_family &&
             field.cardinality == requirement.cardinality &&
             (!requirement.required || field.required),
           do:
             Error.reject!(:invalid_project_configuration, [
               requirement.id <> ": incompatible binding"
             ])

    {requirement, field}
  end

  def validate_slot!(project, slot_id, count) do
    slot = definition!(InputSlotDefinition, project, slot_id)
    compatible_slot!(slot, count)
  end

  defp compatible_slot!(slot, count) do
    unless count >= slot.minimum and count <= slot.maximum,
      do: Error.reject!(:invalid_project_configuration, [slot.id <> ": incompatible item count"])

    slot
  end

  def validate!(project) do
    validate_published!(project)
    requirements = Enum.to_list(rows(InputFieldRequirement, version_id: project.form_version_id))
    questions = Enum.to_list(rows(QuestionDefinition, version_id: project.form_version_id))
    slots = Enum.to_list(rows(InputSlotDefinition, version_id: project.form_version_id))
    validate_contract!(requirements, questions)
    {bindings, policies} = validate_policies!(project, requirements, slots)
    validate_cohort!(project, requirements, bindings, policies)
    validate_explicit!(project, policies)
    :ok
  end

  defp validate_published!(project) do
    unless Ash.exists?(FormVersion,
             query: [filter: [id: project.form_version_id, state: :published]],
             authorize?: false
           ) and
             Ash.exists?(DatasetSchemaVersion,
               query: [filter: [id: project.schema_version_id, state: :published]],
               authorize?: false
             ),
           do: Error.reject!(:invalid_project_configuration)
  end

  defp validate_contract!(requirements, questions) do
    if Enum.any?(requirements, &(&1.intended_use == :image)) or
         Enum.any?(
           questions,
           &(&1.renderer == :image_choice or
               &1.family in [:bounding_boxes, :polygon_regions, :raster_masks])
         ),
       do: Error.reject!(:unsupported_task_contract)
  end

  defp validate_policies!(project, requirements, slots) do
    bindings =
      rows(ProjectInputBinding, project_id: project.id)
      |> Enum.to_list()
      |> Ash.load!(:field_definition, authorize?: false)

    policies = Enum.to_list(rows(ProjectSlotPolicy, project_id: project.id))
    exact!(requirements, bindings, :requirement_id, "complete bindings are required")
    exact!(slots, policies, :input_slot_id, "complete slot policies are required")

    requirements_by_id = Map.new(requirements, &{&1.id, &1})
    slots_by_id = Map.new(slots, &{&1.id, &1})

    for binding <- bindings,
        do:
          compatible_binding!(
            project,
            Map.fetch!(requirements_by_id, binding.requirement_id),
            binding.field_definition
          )

    for policy <- policies,
        do: compatible_slot!(Map.fetch!(slots_by_id, policy.input_slot_id), policy.item_count)

    {bindings, policies}
  end

  defp validate_cohort!(project, requirements, bindings, policies) do
    required_fields = requirements |> Enum.filter(& &1.required) |> MapSet.new(& &1.id)
    required_bindings = Enum.filter(bindings, &MapSet.member?(required_fields, &1.requirement_id))
    field_ids = Enum.map(bindings, & &1.field_definition_id)

    values =
      DatasetValue
      |> Ash.Query.filter(field_definition_id in ^field_ids)
      |> Ash.Query.load(asset_value: :asset)

    item_count =
      ProjectItem
      |> Ash.Query.filter(project_id == ^project.id)
      |> Ash.Query.load(revision: [root_record: [values: values]])
      |> Ash.stream!(authorize?: false, batch_size: 100)
      |> Enum.reduce(0, fn item, count ->
        validate_item!(project, item, required_bindings)
        count + 1
      end)

    required_count = Enum.sum_by(policies, & &1.item_count)

    unless item_count > 0 and item_count >= required_count,
      do:
        Error.reject!(:invalid_project_configuration, [
          project.id <> ": insufficient distinct items"
        ])
  end

  defp validate_item!(project, item, required_bindings) do
    revision = item.revision

    unless revision && revision.item_id == item.item_id &&
             revision.dataset_id == project.dataset_id &&
             revision.schema_version_id == project.schema_version_id,
           do: Error.reject!(:invalid_project_configuration)

    values = revision.root_record.values
    present = MapSet.new(values, & &1.field_definition_id)

    unless Enum.all?(required_bindings, &MapSet.member?(present, &1.field_definition_id)),
      do: Error.reject!(:invalid_project_configuration, [item.id <> ": missing required value"])

    if Enum.any?(values, &(&1.asset_value && &1.asset_value.asset.state != :ready)),
      do:
        Error.reject!(:invalid_project_configuration, [
          item.id <> ": source asset is not ready"
        ])

    :ok
  end

  def validate_group!(project, inputs) do
    expected =
      rows(ProjectSlotPolicy, project_id: project.id)
      |> Map.new(&{&1.input_slot_id, &1.item_count})

    validate_group_shape!(project, inputs, expected)
    ids = Enum.map(inputs, & &1.project_item_id)

    count =
      ProjectItem
      |> Ash.Query.filter(project_id == ^project.id and id in ^ids)
      |> Ash.count!(authorize?: false)

    if count != length(ids), do: Error.reject!(:invalid_project_configuration)
    :ok
  end

  defp validate_group_shape!(project, inputs, expected) do
    actual = Enum.frequencies_by(inputs, & &1.input_slot_id)
    ids = Enum.map(inputs, & &1.project_item_id)

    unless inputs != [] and expected == actual and length(ids) == MapSet.size(MapSet.new(ids)),
      do:
        Error.reject!(:invalid_project_configuration, [project.id <> ": invalid explicit group"])

    positions = Enum.map(inputs, &{&1.input_slot_id, &1.position})

    unless length(positions) == MapSet.size(MapSet.new(positions)),
      do:
        Error.reject!(:invalid_project_configuration, [project.id <> ": duplicate input position"])

    :ok
  end

  defp validate_explicit!(project, policies) do
    expected = Map.new(policies, &{&1.input_slot_id, &1.item_count})

    {coverage, _keys} =
      ExplicitGroup
      |> Ash.Query.filter(project_id == ^project.id)
      |> Ash.Query.load(:inputs)
      |> Ash.stream!(authorize?: false, batch_size: 100)
      |> Enum.reduce({%{}, MapSet.new()}, fn group, {coverage, keys} ->
        # Scoped foreign keys already guarantee each stored input's item and slot.
        inputs = group.inputs
        validate_group_shape!(project, inputs, expected)
        {key, encoded} = GroupIdentity.canonical(inputs)

        unless key == group.canonical_key and not MapSet.member?(keys, encoded),
          do:
            Error.reject!(:invalid_project_configuration, [
              "#{group.id}: duplicate or invalid explicit group"
            ])

        coverage =
          Enum.reduce(
            inputs,
            coverage,
            &Map.update(&2, &1.project_item_id, 1, fn count -> count + 1 end)
          )

        {coverage, MapSet.put(keys, encoded)}
      end)

    for item <- rows(ProjectItem, project_id: project.id) do
      if Map.get(coverage, item.id, 0) < 1,
        do:
          Error.reject!(:invalid_project_configuration, [
            item.id <> ": insufficient explicit coverage"
          ])
    end
  end

  defp exact!(definitions, rows, key, message) do
    unless definitions != [] and
             MapSet.new(definitions, & &1.id) == MapSet.new(rows, &Map.fetch!(&1, key)),
           do: Error.reject!(:invalid_project_configuration, [message])
  end
end
