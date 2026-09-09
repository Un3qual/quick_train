defmodule QuickTrain.Datasets.DatasetImport.Actions.Open do
  @moduledoc false

  alias QuickTrain.DatasetAssetError

  use Ash.Resource.Actions.Implementation

  require Ash.Query

  alias QuickTrain.Datasets.{Dataset, DatasetImport, DatasetSchemaVersion, Fingerprint}

  @impl true
  def run(input, _opts, context) do
    arguments = input.arguments
    actor_id = context.actor.id
    fingerprint = Fingerprint.import_open(arguments.schema_version_id, actor_id)

    Ash.transact([Dataset, DatasetImport, DatasetSchemaVersion], fn ->
      with %{} <- locked_dataset(arguments.organization_id, arguments.dataset_id),
           %{} <- published_schema(arguments),
           {:ok, result} <- existing_or_create(arguments, actor_id, fingerprint) do
        result
      else
        nil -> DatasetAssetError.invalid(:invalid_schema)
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp locked_dataset(organization_id, dataset_id) do
    Dataset
    |> Ash.Query.filter(id == ^dataset_id and organization_id == ^organization_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(authorize?: false)
  end

  defp published_schema(arguments) do
    DatasetSchemaVersion
    |> Ash.Query.filter(
      id == ^arguments.schema_version_id and dataset_id == ^arguments.dataset_id and
        state == :published
    )
    |> Ash.read_one!(authorize?: false)
  end

  defp existing_or_create(arguments, actor_id, fingerprint) do
    existing =
      DatasetImport
      |> Ash.Query.filter(
        organization_id == ^arguments.organization_id and dataset_id == ^arguments.dataset_id and
          idempotency_key == ^arguments.idempotency_key
      )
      |> Ash.read_one!(authorize?: false)

    cond do
      existing && existing.open_fingerprint == fingerprint ->
        {:ok, existing}

      existing ->
        DatasetAssetError.invalid(:idempotency_conflict)

      true ->
        expires_at =
          DateTime.add(
            DateTime.utc_now(),
            Application.fetch_env!(:quick_train, :dataset_imports)[:open_lifetime_seconds],
            :second
          )

        DatasetImport
        |> Ash.Changeset.for_create(:create_internal, %{
          organization_id: arguments.organization_id,
          dataset_id: arguments.dataset_id,
          schema_version_id: arguments.schema_version_id,
          initiated_by_id: actor_id,
          idempotency_key: arguments.idempotency_key,
          open_fingerprint: fingerprint,
          open_expires_at: expires_at
        })
        |> Ash.create(authorize?: false)
    end
  end
end
