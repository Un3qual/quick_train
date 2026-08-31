defmodule QuickTrain.Datasets.DatasetFieldDefinition.Actions.AddToDraft do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias QuickTrain.Datasets.{DatasetFieldDefinition, SchemaVersionBoundary}

  @impl true
  def run(input, _opts, _context) do
    %{organization_id: organization_id, record_type_id: record_type_id} = input.arguments

    SchemaVersionBoundary.with_record_type(
      organization_id,
      record_type_id,
      [DatasetFieldDefinition],
      fn record_type ->
        attributes =
          input.arguments
          |> Map.take([:key, :name, :value_family, :cardinality, :required])
          |> Map.put(:record_type_id, record_type.id)

        DatasetFieldDefinition
        |> Ash.Changeset.for_create(:create_internal, attributes)
        |> Ash.create!(authorize?: false)
      end
    )
  end
end
