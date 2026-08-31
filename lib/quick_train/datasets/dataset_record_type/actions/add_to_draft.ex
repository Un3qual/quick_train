defmodule QuickTrain.Datasets.DatasetRecordType.Actions.AddToDraft do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias QuickTrain.Datasets.{DatasetRecordType, SchemaVersionBoundary}

  @impl true
  def run(input, _opts, _context) do
    %{organization_id: organization_id, schema_version_id: schema_version_id} =
      input.arguments

    SchemaVersionBoundary.with_draft(
      organization_id,
      schema_version_id,
      fn schema ->
        DatasetRecordType
        |> Ash.Changeset.for_create(:create_internal, %{
          schema_version_id: schema.id,
          key: input.arguments.key,
          name: input.arguments.name
        })
        |> Ash.create!(authorize?: false)
      end
    )
  end
end
