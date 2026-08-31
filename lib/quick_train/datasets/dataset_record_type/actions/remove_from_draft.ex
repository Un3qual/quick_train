defmodule QuickTrain.Datasets.DatasetRecordType.Actions.RemoveFromDraft do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias QuickTrain.Datasets.SchemaVersionBoundary

  @impl true
  def run(input, _opts, _context) do
    %{organization_id: organization_id, record_type_id: record_type_id} = input.arguments

    SchemaVersionBoundary.with_record_type(
      organization_id,
      record_type_id,
      [],
      fn record_type ->
        Ash.destroy(record_type, action: :destroy_internal, authorize?: false)
      end
    )
  end
end
