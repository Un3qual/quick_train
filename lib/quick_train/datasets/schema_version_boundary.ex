defmodule QuickTrain.Datasets.SchemaVersionBoundary do
  @moduledoc false

  alias QuickTrain.DatasetAssetError
  alias QuickTrain.Datasets.{DatasetFieldDefinition, DatasetRecordType, DatasetSchemaVersion}

  import Ash.Expr

  def with_draft(organization_id, schema_version_id, callback) do
    Ash.transact(DatasetSchemaVersion, fn ->
      case locked_schema(organization_id, id: schema_version_id) do
        nil -> DatasetAssetError.invalid(:invalid_schema)
        %{state: :draft} = schema -> callback.(schema)
        %{} -> DatasetAssetError.invalid(:schema_not_draft)
      end
    end)
  end

  def with_record_type(organization_id, record_type_id, callback) do
    Ash.transact(DatasetSchemaVersion, fn ->
      with %{state: :draft} = schema <-
             locked_schema(organization_id, expr(exists(record_types, id == ^record_type_id))),
           %{} = current <-
             DatasetRecordType.get_internal!(record_type_id,
               query: [filter: [schema_version_id: schema.id]],
               authorize?: false
             ) do
        callback.(current)
      else
        %{state: _state} -> DatasetAssetError.invalid(:schema_not_draft)
        _other -> DatasetAssetError.invalid(:invalid_schema)
      end
    end)
  end

  def with_field_definition(organization_id, field_definition_id, callback) do
    Ash.transact(DatasetSchemaVersion, fn ->
      with %{state: :draft} = schema <-
             locked_schema(
               organization_id,
               expr(exists(record_types.field_definitions, id == ^field_definition_id))
             ),
           %{} = current <-
             DatasetFieldDefinition.get_internal!(field_definition_id,
               query: [filter: [record_type: [schema_version_id: schema.id]]],
               authorize?: false
             ) do
        callback.(current)
      else
        %{state: _state} -> DatasetAssetError.invalid(:schema_not_draft)
        _other -> DatasetAssetError.invalid(:invalid_schema)
      end
    end)
  end

  defp locked_schema(organization_id, filter) do
    DatasetSchemaVersion.get_internal!(
      query: [
        filter: [and: [filter, [dataset: [organization_id: organization_id]]]],
        lock: :for_update
      ],
      authorize?: false
    )
  end
end
