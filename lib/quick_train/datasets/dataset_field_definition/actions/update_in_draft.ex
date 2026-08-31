defmodule QuickTrain.Datasets.DatasetFieldDefinition.Actions.UpdateInDraft do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias QuickTrain.Datasets.SchemaVersionBoundary

  @impl true
  def run(input, _opts, _context) do
    %{organization_id: organization_id, field_definition_id: field_definition_id} =
      input.arguments

    SchemaVersionBoundary.with_field_definition(
      organization_id,
      field_definition_id,
      fn field ->
        attributes =
          Map.take(input.arguments, [:key, :name, :value_family, :cardinality, :required])

        field
        |> Ash.Changeset.for_update(:update_internal, attributes)
        |> Ash.update!(authorize?: false)
      end
    )
  end
end
