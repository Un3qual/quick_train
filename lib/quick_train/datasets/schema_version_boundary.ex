defmodule QuickTrain.Datasets.SchemaVersionBoundary do
  @moduledoc false

  alias QuickTrain.ProductError

  require Ash.Query

  alias QuickTrain.Datasets.{DatasetFieldDefinition, DatasetRecordType, DatasetSchemaVersion}

  def with_draft(organization_id, schema_version_id, callback) do
    Ash.transact([DatasetSchemaVersion, DatasetRecordType], fn ->
      case locked_schema(organization_id, schema_version_id) do
        nil -> ProductError.invalid(:invalid_schema)
        %{state: :draft} = schema -> callback.(schema)
        %{} -> ProductError.invalid(:schema_not_draft)
      end
    end)
  end

  def with_record_type(organization_id, record_type_id, resources, callback) do
    Ash.transact([DatasetSchemaVersion, DatasetRecordType | resources], fn ->
      with %{} = record_type <- scoped_record_type(organization_id, record_type_id),
           %{state: :draft} = schema <-
             locked_schema(organization_id, record_type.schema_version_id),
           %{} = current <- current_record_type(record_type.id, schema.id) do
        callback.(current)
      else
        %{state: _state} -> ProductError.invalid(:schema_not_draft)
        _other -> ProductError.invalid(:invalid_schema)
      end
    end)
  end

  def with_field_definition(organization_id, field_definition_id, callback) do
    Ash.transact(
      [DatasetSchemaVersion, DatasetRecordType, DatasetFieldDefinition],
      fn ->
        with %{} = field <- scoped_field(organization_id, field_definition_id),
             %{state: :draft} <-
               locked_schema(organization_id, field.record_type.schema_version_id),
             %{} = current <- current_field(field.id, field.record_type_id) do
          callback.(current)
        else
          %{state: _state} -> ProductError.invalid(:schema_not_draft)
          _other -> ProductError.invalid(:invalid_schema)
        end
      end
    )
  end

  defp locked_schema(organization_id, schema_version_id) do
    DatasetSchemaVersion
    |> Ash.Query.filter(id == ^schema_version_id and dataset.organization_id == ^organization_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(authorize?: false)
  end

  defp scoped_record_type(organization_id, record_type_id) do
    DatasetRecordType
    |> Ash.Query.filter(
      id == ^record_type_id and
        schema_version.dataset.organization_id == ^organization_id
    )
    |> Ash.read_one!(authorize?: false)
  end

  defp current_record_type(record_type_id, schema_version_id) do
    DatasetRecordType
    |> Ash.Query.filter(id == ^record_type_id and schema_version_id == ^schema_version_id)
    |> Ash.read_one!(authorize?: false)
  end

  defp scoped_field(organization_id, field_definition_id) do
    DatasetFieldDefinition
    |> Ash.Query.filter(
      id == ^field_definition_id and
        record_type.schema_version.dataset.organization_id == ^organization_id
    )
    |> Ash.Query.load(record_type: :schema_version)
    |> Ash.read_one!(authorize?: false)
  end

  defp current_field(field_definition_id, record_type_id) do
    DatasetFieldDefinition
    |> Ash.Query.filter(id == ^field_definition_id and record_type_id == ^record_type_id)
    |> Ash.read_one!(authorize?: false)
  end
end
