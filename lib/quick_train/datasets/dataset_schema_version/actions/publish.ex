defmodule QuickTrain.Datasets.DatasetSchemaVersion.Actions.Publish do
  @moduledoc false

  alias QuickTrain.DatasetAssetError

  use Ash.Resource.Actions.Implementation

  alias QuickTrain.Datasets
  alias QuickTrain.Datasets.SchemaVersionBoundary

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
    case Datasets.publish_schema_version_internal(
           schema.id,
           %{
             root_record_type_id: root_record_type_id,
             max_fields_per_row:
               Application.fetch_env!(:quick_train, :dataset_imports)
               |> Keyword.fetch!(:max_fields_per_row)
           },
           authorize?: false,
           bulk_options: [strategy: [:atomic]]
         ) do
      {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{}]}} ->
        DatasetAssetError.invalid(:invalid_schema)

      {:ok, published} ->
        published

      {:error, error} ->
        {:error, error}
    end
  end
end
