defmodule QuickTrain.Datasets.Changes.AllocateSchemaVersion do
  @moduledoc false
  use Ash.Resource.Change
  alias QuickTrain.{DatasetAssetError, Datasets}
  alias QuickTrain.Datasets.DatasetSchemaVersion

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      dataset_id = Ash.Changeset.get_attribute(changeset, :dataset_id)
      organization_id = Ash.Changeset.get_argument(changeset, :organization_id)

      case Datasets.get_dataset!(dataset_id,
             query: [filter: [organization_id: organization_id], lock: :for_update],
             not_found_error?: false,
             authorize?: false
           ) do
        nil ->
          Ash.Changeset.add_error(
            changeset,
            DatasetAssetError.exception(category: :invalid_schema)
          )

        dataset ->
          version =
            Ash.max!(DatasetSchemaVersion, :version,
              query: [filter: [dataset_id: dataset.id]],
              default: 0,
              authorize?: false
            ) + 1

          Ash.Changeset.force_change_attribute(changeset, :version, version)
      end
    end)
  end
end
