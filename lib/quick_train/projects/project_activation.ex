defmodule QuickTrain.Projects.ProjectActivation do
  @moduledoc false
  alias QuickTrain.Projects.{
    Error,
    ExplicitGroup,
    ExplicitGroupInput,
    GroupIdentity,
    ProjectInputBinding,
    ProjectItem,
    ProjectQuestionPolicy,
    ProjectSlotPolicy
  }

  alias QuickTrain.Datasets.{
    DatasetFieldDefinition,
    DatasetItemRevision,
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

    unless field && field.value_family == requirement.value_family &&
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
    {bindings, policies} = validate_policies!(project, requirements, questions, slots)
    validate_cohort!(project, requirements, bindings, policies)
    if project.selection_mode == :explicit, do: validate_explicit!(project)
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

  defp validate_policies!(project, requirements, questions, slots) do
    bindings = Enum.to_list(rows(ProjectInputBinding, project_id: project.id))
    policies = Enum.to_list(rows(ProjectSlotPolicy, project_id: project.id))
    question_policies = Enum.to_list(rows(ProjectQuestionPolicy, project_id: project.id))
    exact!(requirements, bindings, :requirement_id, "complete bindings are required")
    exact!(slots, policies, :input_slot_id, "complete slot policies are required")
    exact!(questions, question_policies, :question_id, "complete question policies are required")

    for binding <- bindings,
        do: validate_binding!(project, binding.requirement_id, binding.field_definition_id)

    for policy <- policies, do: validate_slot!(project, policy.input_slot_id, policy.item_count)

    {bindings, policies}
  end

  defp validate_cohort!(project, requirements, bindings, policies) do
    required_fields = requirements |> Enum.filter(& &1.required) |> MapSet.new(& &1.id)
    required_bindings = Enum.filter(bindings, &MapSet.member?(required_fields, &1.requirement_id))
    field_ids = Enum.map(bindings, & &1.field_definition_id)

    item_count =
      rows(ProjectItem, project_id: project.id)
      |> Enum.reduce(0, fn item, count ->
        validate_item!(project, item, field_ids, required_bindings)
        count + 1
      end)

    required_count = Enum.sum_by(policies, & &1.item_count)

    unless item_count > 0 and item_count >= required_count,
      do:
        Error.reject!(:invalid_project_configuration, [
          project.id <> ": insufficient distinct items"
        ])
  end

  defp validate_item!(project, item, field_ids, required_bindings) do
    revision =
      DatasetItemRevision
      |> Ash.Query.filter(
        id == ^item.revision_id and item_id == ^item.item_id and
          dataset_id == ^project.dataset_id and
          schema_version_id == ^project.schema_version_id
      )
      |> Ash.read_one!(authorize?: false)

    if is_nil(revision), do: Error.reject!(:invalid_project_configuration)

    values =
      DatasetValue
      |> Ash.Query.filter(
        record_id == ^revision.root_record_id and field_definition_id in ^field_ids
      )
      |> Ash.stream!(authorize?: false, batch_size: 100)
      |> Enum.to_list()

    present = MapSet.new(values, & &1.field_definition_id)

    unless Enum.all?(required_bindings, &MapSet.member?(present, &1.field_definition_id)),
      do: Error.reject!(:invalid_project_configuration, [item.id <> ": missing required value"])

    value_ids = Enum.map(values, & &1.id)

    if DatasetValue.Asset
       |> Ash.Query.filter(dataset_value_id in ^value_ids and asset.state != :ready)
       |> Ash.exists?(authorize?: false),
       do:
         Error.reject!(:invalid_project_configuration, [
           item.id <> ": source asset is not ready"
         ])

    :ok
  end

  def validate_group!(project, inputs) do
    policies = Enum.to_list(rows(ProjectSlotPolicy, project_id: project.id))
    expected = Map.new(policies, &{&1.input_slot_id, &1.item_count})
    actual = Enum.frequencies_by(inputs, & &1.input_slot_id)
    ids = Enum.map(inputs, & &1.project_item_id)

    unless inputs != [] and expected == actual and length(ids) == MapSet.size(MapSet.new(ids)),
      do:
        Error.reject!(:invalid_project_configuration, [project.id <> ": invalid explicit group"])

    for input <- inputs do
      unless Ash.exists?(ProjectItem,
               query: [filter: [id: input.project_item_id, project_id: project.id]],
               authorize?: false
             ),
             do: Error.reject!(:invalid_project_configuration)

      definition!(InputSlotDefinition, project, input.input_slot_id)
    end

    positions = Enum.map(inputs, &{&1.input_slot_id, &1.position})

    unless length(positions) == MapSet.size(MapSet.new(positions)),
      do:
        Error.reject!(:invalid_project_configuration, [project.id <> ": duplicate input position"])

    :ok
  end

  defp validate_explicit!(project) do
    {coverage, _keys} =
      rows(ExplicitGroup, project_id: project.id)
      |> Enum.reduce({%{}, MapSet.new()}, fn group, {coverage, keys} ->
        inputs =
          Enum.to_list(rows(ExplicitGroupInput, project_id: project.id, group_id: group.id))

        validate_group!(project, inputs)
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
      if Map.get(coverage, item.id, 0) < project.coverage_target,
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
