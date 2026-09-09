defmodule QuickTrain.Datasets.DatasetSchemaVersion.Actions.CreateDraft do
  @moduledoc false

  alias QuickTrain.DatasetAssetError

  use Ash.Resource.Actions.Implementation

  require Ash.Query

  alias QuickTrain.Datasets.{Dataset, DatasetSchemaVersion}

  @impl true
  def run(input, _opts, _context) do
    %{organization_id: organization_id, dataset_id: dataset_id} = input.arguments

    Ash.transact([Dataset, DatasetSchemaVersion], fn ->
      case locked_dataset(organization_id, dataset_id) do
        nil ->
          DatasetAssetError.invalid(:invalid_schema)

        dataset ->
          DatasetSchemaVersion
          |> Ash.Changeset.for_create(:create_internal, %{
            dataset_id: dataset.id,
            version: next_version(dataset.id)
          })
          |> Ash.create!(authorize?: false)
      end
    end)
  end

  defp locked_dataset(organization_id, dataset_id) do
    Dataset
    |> Ash.Query.filter(id == ^dataset_id and organization_id == ^organization_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(authorize?: false)
  end

  defp next_version(dataset_id) do
    latest =
      DatasetSchemaVersion
      |> Ash.Query.filter(dataset_id == ^dataset_id)
      |> Ash.Query.sort(version: :desc)
      |> Ash.Query.limit(1)
      |> Ash.read_one!(authorize?: false)

    if latest, do: latest.version + 1, else: 1
  end
end
