defmodule QuickTrain.Datasets.Changes.OpenImport do
  @moduledoc false
  use Ash.Resource.Change
  alias QuickTrain.{DatasetAssetError, Datasets}
  alias QuickTrain.Datasets.Fingerprint

  @impl true
  def change(changeset, _opts, context) do
    changeset
    |> Ash.Changeset.before_action(&prepare(&1, context.actor))
    |> Ash.Changeset.after_action(fn changeset, import ->
      if import.open_fingerprint == Ash.Changeset.get_attribute(changeset, :open_fingerprint),
        do: {:ok, import},
        else: DatasetAssetError.invalid(:idempotency_conflict)
    end)
  end

  defp prepare(changeset, actor) do
    schema_id = Ash.Changeset.get_attribute(changeset, :schema_version_id)

    schema =
      Datasets.get_published_record_schema!(
        Ash.Changeset.get_attribute(changeset, :organization_id),
        Ash.Changeset.get_attribute(changeset, :dataset_id),
        schema_id,
        authorize?: false
      )

    if schema do
      Ash.Changeset.force_change_attributes(changeset,
        initiated_by_id: actor.id,
        open_fingerprint: Fingerprint.import_open(schema_id, actor.id),
        open_expires_at:
          DateTime.add(
            DateTime.utc_now(),
            Application.fetch_env!(:quick_train, :dataset_imports)[:open_lifetime_seconds],
            :second
          )
      )
    else
      Ash.Changeset.add_error(changeset, DatasetAssetError.exception(category: :invalid_schema))
    end
  end
end
