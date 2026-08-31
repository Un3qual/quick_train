defmodule QuickTrain.Datasets.DatasetFieldDefinition.Actions.RemoveFromDraft do
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
      [],
      fn _schema, field ->
        case Ash.destroy(field, action: :destroy_internal, authorize?: false) do
          :ok -> :ok
          {:ok, _record} -> :ok
          {:error, error} -> {:error, error}
        end
      end
    )
  end
end
