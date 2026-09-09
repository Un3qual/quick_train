defmodule QuickTrain.Datasets.DatasetSchemaVersion.Actions.CreateDraft do
  @moduledoc false

  alias QuickTrain.DatasetAssetError

  use Ash.Resource.Actions.Implementation

  alias QuickTrain.Datasets
  alias QuickTrain.Datasets.{Dataset, DatasetSchemaVersion}

  @impl true
  def run(input, _opts, _context) do
    %{organization_id: organization_id, dataset_id: dataset_id} = input.arguments

    Ash.transact([Dataset, DatasetSchemaVersion], fn ->
      case locked_dataset(organization_id, dataset_id) do
        nil ->
          DatasetAssetError.invalid(:invalid_schema)

        dataset ->
          Datasets.create_schema_version_internal!(
            %{
              dataset_id: dataset.id,
              version: next_version(dataset.id)
            },
            authorize?: false
          )
      end
    end)
  end

  defp locked_dataset(organization_id, dataset_id) do
    Datasets.get_dataset!(dataset_id,
      query: [filter: [organization_id: organization_id], lock: :for_update],
      not_found_error?: false,
      authorize?: false
    )
  end

  defp next_version(dataset_id) do
    Ash.max!(DatasetSchemaVersion, :version,
      query: [filter: [dataset_id: dataset_id]],
      default: 0,
      authorize?: false
    ) + 1
  end
end
