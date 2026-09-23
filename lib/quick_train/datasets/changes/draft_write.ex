defmodule QuickTrain.Datasets.Changes.DraftWrite do
  @moduledoc false
  use Ash.Resource.Change

  alias QuickTrain.DatasetAssetError
  alias QuickTrain.Datasets.{DatasetFieldDefinition, DatasetRecordType, DatasetSchemaVersion}
  require Ash.Expr

  @impl true
  def change(changeset, _opts, _context),
    do: Ash.Changeset.before_action(changeset, &lock/1)

  defp lock(changeset) do
    organization_id = Ash.Changeset.get_argument(changeset, :organization_id)
    filter = schema_filter(changeset)

    schema =
      DatasetSchemaVersion.get_internal!(
        query: [
          filter: [and: [filter, [dataset: [organization_id: organization_id]]]],
          lock: :for_update
        ],
        authorize?: false
      )

    cond do
      is_nil(schema) -> reject!(:invalid_schema)
      schema.state != :draft -> reject!(:schema_not_draft)
      true -> refresh(changeset, schema)
    end
  rescue
    error in [DatasetAssetError, Ash.Error.Invalid] -> Ash.Changeset.add_error(changeset, error)
  end

  defp schema_filter(%{resource: DatasetSchemaVersion, data: record}), do: [id: record.id]

  defp schema_filter(%{resource: DatasetRecordType, action_type: :create} = changeset),
    do: [id: Ash.Changeset.get_attribute(changeset, :schema_version_id)]

  defp schema_filter(%{resource: DatasetRecordType, data: record}),
    do: Ash.Expr.expr(exists(record_types, id == ^record.id))

  defp schema_filter(%{resource: DatasetFieldDefinition, action_type: :create} = changeset),
    do:
      Ash.Expr.expr(
        exists(record_types, id == ^Ash.Changeset.get_attribute(changeset, :record_type_id))
      )

  defp schema_filter(%{resource: DatasetFieldDefinition, data: record}),
    do: Ash.Expr.expr(exists(record_types.field_definitions, id == ^record.id))

  defp refresh(%{action_type: :create} = changeset, _schema), do: changeset

  defp refresh(changeset, schema) do
    record =
      case changeset.resource do
        DatasetSchemaVersion ->
          schema

        DatasetRecordType ->
          DatasetRecordType.get_internal!(changeset.data.id,
            query: [filter: [schema_version_id: schema.id]],
            authorize?: false
          )

        DatasetFieldDefinition ->
          DatasetFieldDefinition.get_internal!(changeset.data.id,
            query: [filter: [record_type: [schema_version_id: schema.id]]],
            authorize?: false
          )
      end

    if is_nil(record), do: reject!(:invalid_schema)

    %{changeset | data: record}
    |> Ash.Changeset.force_change_attributes(changeset.casted_attributes)
  end

  @spec reject!(atom()) :: no_return()
  defp reject!(category), do: raise(DatasetAssetError, category: category)
end
