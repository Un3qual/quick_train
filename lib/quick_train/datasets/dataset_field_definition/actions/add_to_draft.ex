defmodule QuickTrain.Datasets.DatasetFieldDefinition.Actions.AddToDraft do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias QuickTrain.Datasets.{DatasetFieldDefinition, SchemaVersionBoundary}

  @impl true
  def run(input, _opts, _context) do
    %{organization_id: organization_id, record_type_id: record_type_id} = input.arguments

    with :ok <- validate_shape(input.arguments) do
      SchemaVersionBoundary.with_record_type(
        organization_id,
        record_type_id,
        [DatasetFieldDefinition],
        fn _schema, record_type ->
          DatasetFieldDefinition
          |> Ash.Changeset.for_create(
            :create_internal,
            attributes(input.arguments, record_type.id)
          )
          |> Ash.create!(authorize?: false)
        end
      )
    end
  end

  def attributes(arguments, record_type_id) do
    %{
      record_type_id: record_type_id,
      key: arguments.key,
      name: arguments.name,
      value_family: arguments.value_family,
      cardinality: arguments.cardinality,
      required: arguments.required
    }
  end

  def validate_shape(%{value_family: value_family, cardinality: cardinality}) do
    cond do
      value_family not in ~w(text integer decimal boolean utc_datetime asset) ->
        {:error, :invalid_value_family}

      cardinality != "single" ->
        {:error, :invalid_cardinality}

      true ->
        :ok
    end
  end
end
