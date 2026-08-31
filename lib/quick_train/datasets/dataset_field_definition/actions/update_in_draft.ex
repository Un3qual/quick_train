defmodule QuickTrain.Datasets.DatasetFieldDefinition.Actions.UpdateInDraft do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias QuickTrain.Datasets.DatasetFieldDefinition.Actions.AddToDraft
  alias QuickTrain.Datasets.SchemaVersionBoundary

  @impl true
  def run(input, _opts, _context) do
    %{organization_id: organization_id, field_definition_id: field_definition_id} =
      input.arguments

    with :ok <- AddToDraft.validate_shape(input.arguments) do
      SchemaVersionBoundary.with_field_definition(
        organization_id,
        field_definition_id,
        [],
        fn _schema, field ->
          field
          |> Ash.Changeset.for_update(
            :update_internal,
            input.arguments
            |> AddToDraft.attributes(field.record_type_id)
            |> Map.delete(:record_type_id)
          )
          |> Ash.update!(authorize?: false)
        end
      )
    end
  end
end
