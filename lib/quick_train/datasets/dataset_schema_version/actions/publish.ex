defmodule QuickTrain.Datasets.DatasetSchemaVersion.Actions.Publish do
  @moduledoc false

  alias QuickTrain.ProductError

  use Ash.Resource.Actions.Implementation

  require Ash.Query

  alias QuickTrain.Datasets.{DatasetRecordType, SchemaVersionBoundary}

  @impl true
  def run(input, _opts, _context) do
    %{
      organization_id: organization_id,
      schema_version_id: schema_version_id,
      root_record_type_id: root_record_type_id
    } = input.arguments

    SchemaVersionBoundary.with_draft(
      organization_id,
      schema_version_id,
      fn schema -> publish(schema, root_record_type_id) end
    )
  end

  defp publish(schema, root_record_type_id) do
    root =
      DatasetRecordType
      |> Ash.Query.filter(id == ^root_record_type_id and schema_version_id == ^schema.id)
      |> Ash.read_one!(authorize?: false)

    if root do
      schema
      |> Ash.Changeset.for_update(:publish_internal, %{
        root_record_type_id: root.id,
        published_at: DateTime.utc_now()
      })
      |> Ash.update!(authorize?: false)
    else
      ProductError.invalid(:invalid_schema)
    end
  end
end
