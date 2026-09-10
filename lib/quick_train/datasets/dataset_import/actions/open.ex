defmodule QuickTrain.Datasets.DatasetImport.Actions.Open do
  @moduledoc false

  alias QuickTrain.{DatasetAssetError, Datasets}
  alias QuickTrain.Datasets.{DatasetSchemaVersion, Fingerprint}

  use Ash.Resource.Actions.Implementation

  @impl true
  def run(input, _opts, context) do
    arguments = input.arguments
    actor_id = context.actor.id
    fingerprint = Fingerprint.import_open(arguments.schema_version_id, actor_id)

    with %{} <- published_schema(arguments),
         {:ok, import} <- create_or_get(arguments, actor_id, fingerprint) do
      if import.open_fingerprint == fingerprint,
        do: {:ok, import},
        else: DatasetAssetError.invalid(:idempotency_conflict)
    else
      nil -> DatasetAssetError.invalid(:invalid_schema)
      {:error, error} -> {:error, error}
    end
  end

  defp published_schema(arguments) do
    DatasetSchemaVersion.get_internal!(
      query: [
        filter: [
          id: arguments.schema_version_id,
          dataset_id: arguments.dataset_id,
          dataset: [organization_id: arguments.organization_id],
          state: :published
        ]
      ],
      authorize?: false
    )
  end

  defp create_or_get(arguments, actor_id, fingerprint) do
    expires_at =
      DateTime.add(
        DateTime.utc_now(),
        Application.fetch_env!(:quick_train, :dataset_imports)[:open_lifetime_seconds],
        :second
      )

    Datasets.create_import_internal(
      %{
        organization_id: arguments.organization_id,
        dataset_id: arguments.dataset_id,
        schema_version_id: arguments.schema_version_id,
        initiated_by_id: actor_id,
        idempotency_key: arguments.idempotency_key,
        open_fingerprint: fingerprint,
        open_expires_at: expires_at
      },
      upsert?: true,
      upsert_identity: :organization_dataset_key,
      upsert_fields: [],
      authorize?: false
    )
  end
end
