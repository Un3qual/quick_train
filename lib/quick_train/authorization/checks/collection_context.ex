defmodule QuickTrain.Authorization.Checks.CollectionContext do
  @moduledoc false
  use Ash.Policy.FilterCheck
  alias QuickTrain.Datasets.{DatasetFieldDefinition, DatasetValue}
  alias QuickTrain.Forms.FormVersion
  alias QuickTrain.Tasks.Access.ReadAccess
  alias QuickTrain.Tasks.Attempts.Attempt
  alias QuickTrain.Tasks.{Task, TaskInput}
  import Ash.Expr

  def describe(_),
    do: "an exact published definition or bound value of currently authorized issued work"

  def filter(%{id: _} = actor, %{resource: resource, query: query}, _opts) do
    if is_map(query.context[:accessing_from]),
      do: definition_filter(resource, actor),
      else: false
  end

  def filter(_, _, _), do: false

  defp definition_filter(FormVersion, actor) do
    live = ReadAccess.live_attempt(actor)
    results = ReadAccess.result_authority(actor)

    expr(
      exists(Attempt, form_version_id == parent(id) and ^live) or
        exists(Task, form_version_id == parent(id) and ^results)
    )
  end

  defp definition_filter(DatasetValue, actor), do: value_access(actor)

  defp definition_filter(resource, actor)
       when resource in [
              DatasetValue.Text,
              DatasetValue.Integer,
              DatasetValue.Decimal,
              DatasetValue.Boolean,
              DatasetValue.DateTime,
              DatasetValue.Asset
            ] do
    values = value_access(actor)
    expr(exists(DatasetValue, id == parent(dataset_value_id) and ^values))
  end

  defp definition_filter(QuickTrain.Assets.Asset, actor) do
    values = value_access(actor)

    expr(
      exists(
        DatasetValue.Asset,
        asset_id == parent(id) and
          exists(DatasetValue, id == parent(dataset_value_id) and ^values)
      )
    )
  end

  defp definition_filter(DatasetFieldDefinition, actor) do
    input_access = ReadAccess.authorized_filter(TaskInput, actor)

    expr(
      exists(
        TaskInput,
        ^input_access and
          exists(
            project.bindings,
            field_definition_id == parent(parent(id)) and
              requirement.input_slot_id == parent(input_slot_id)
          )
      )
    )
  end

  defp definition_filter(_resource, actor) do
    live = ReadAccess.live_attempt(actor)
    results = ReadAccess.result_authority(actor)

    expr(
      exists(Attempt, form_version_id == parent(version_id) and ^live) or
        exists(Task, form_version_id == parent(version_id) and ^results)
    )
  end

  defp value_access(actor) do
    input_access = ReadAccess.authorized_filter(TaskInput, actor)

    expr(
      exists(
        TaskInput,
        revision.root_record_id == parent(record_id) and ^input_access and
          exists(
            project.bindings,
            field_definition_id == parent(parent(field_definition_id)) and
              requirement.input_slot_id == parent(input_slot_id)
          )
      )
    )
  end
end
