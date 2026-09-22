defmodule QuickTrain.Datasets.Changes.PublishSchema do
  @moduledoc false
  use Ash.Resource.Change
  alias QuickTrain.DatasetAssetError
  alias QuickTrain.Datasets.DatasetRecordType
  require Ash.Query

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      root_id = Ash.Changeset.get_argument(changeset, :root_record_type_id)

      cap =
        Application.fetch_env!(:quick_train, :dataset_imports)
        |> Keyword.fetch!(:max_fields_per_row)

      valid? =
        DatasetRecordType
        |> Ash.Query.filter(
          id == ^root_id and schema_version_id == ^changeset.data.id and
            required_field_count <= ^cap
        )
        |> Ash.exists?(authorize?: false)

      if valid? do
        Ash.Changeset.force_change_attributes(changeset,
          root_record_type_id: root_id,
          state: :published,
          published_at: DateTime.utc_now()
        )
      else
        Ash.Changeset.add_error(changeset, DatasetAssetError.exception(category: :invalid_schema))
      end
    end)
  end
end
