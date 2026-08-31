defmodule QuickTrain.Datasets.DatasetRecordType.Actions.UpdateInDraft do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias QuickTrain.Datasets.{DatasetRecordType, SchemaVersionBoundary}

  @impl true
  def run(input, _opts, _context) do
    %{organization_id: organization_id, record_type_id: record_type_id} = input.arguments

    SchemaVersionBoundary.with_record_type(
      organization_id,
      record_type_id,
      [DatasetRecordType],
      fn _schema, record_type ->
        record_type
        |> Ash.Changeset.for_update(:update_internal, %{
          key: input.arguments.key,
          name: input.arguments.name
        })
        |> Ash.update!(authorize?: false)
      end
    )
  end
end
