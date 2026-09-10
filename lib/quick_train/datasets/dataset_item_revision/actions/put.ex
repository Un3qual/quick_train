defmodule QuickTrain.Datasets.DatasetItemRevision.Actions.Put do
  # The nested branch is the item-lock transaction's explicit rollback state machine.
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  require Ash.Query

  alias QuickTrain.{AshError, DatasetAssetError, Datasets}

  alias QuickTrain.Datasets.{
    DatasetItem,
    DatasetItemRevision,
    DatasetRecord,
    Fingerprint
  }

  alias QuickTrain.Datasets.DatasetItemRevision.Result, as: RevisionResult
  alias QuickTrain.Datasets.DatasetRecord.Values

  @item_conflicts ["dataset_items_pkey", "dataset_items_dataset_external_key_index"]
  @attempts 2

  @impl true
  def run(input, _opts, _context) do
    arguments = input.arguments

    with %{} = schema <- published_schema(arguments),
         {:ok, occurrences} <- occurrences(schema, arguments),
         fingerprint <-
           Fingerprint.revision(schema.id, schema.root_record_type_id, occurrences) do
      put(arguments, schema, occurrences, fingerprint, @attempts)
    else
      nil -> DatasetAssetError.invalid(:invalid_schema)
      {:error, reason} -> DatasetAssetError.wrap({:error, reason})
    end
  end

  defp occurrences(schema, %{candidate_record_id: record_id} = arguments) do
    record =
      DatasetRecord
      |> Ash.Query.filter(
        id == ^record_id and organization_id == ^arguments.organization_id and
          dataset_id == ^arguments.dataset_id and schema_version_id == ^schema.id and
          record_type_id == ^schema.root_record_type_id
      )
      |> Ash.read_one!(authorize?: false)

    if record,
      do: {:ok, Values.load(record, schema)},
      else: DatasetAssetError.invalid(:invalid_value)
  end

  defp occurrences(schema, arguments), do: Values.normalize(schema, arguments.values)

  defp published_schema(arguments) do
    Datasets.get_published_record_schema!(
      arguments.organization_id,
      arguments.dataset_id,
      arguments.schema_version_id,
      authorize?: false
    )
  end

  defp put(arguments, schema, occurrences, fingerprint, attempts) do
    resources = [DatasetItem, DatasetItemRevision, DatasetRecord]

    result =
      Ash.transact(resources, fn ->
        with {:ok, item} <- stable_item(arguments),
             :ok <- matching_identity(item, arguments),
             :ok <- validate_assets(arguments, occurrences) do
          latest = latest_revision(item.id)

          if latest && latest.fingerprint == fingerprint do
            %RevisionResult{changed: false, item: item, revision: latest}
          else
            revision = create_revision!(arguments, schema, item, latest, occurrences, fingerprint)
            %RevisionResult{changed: true, item: item, revision: revision}
          end
        else
          {:error, reason} -> DatasetAssetError.wrap({:error, reason})
        end
      end)

    case result do
      {:ok, %RevisionResult{} = revision_result} ->
        {:ok, revision_result}

      {:error, error} when attempts > 1 ->
        if AshError.constraint?(error, @item_conflicts) do
          put(arguments, schema, occurrences, fingerprint, attempts - 1)
        else
          {:error, error}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  # Append already validated the immutable candidate and its ready asset references.
  defp validate_assets(%{candidate_record_id: _record_id}, _occurrences), do: :ok

  defp validate_assets(arguments, occurrences),
    do: Values.validate_assets(arguments.organization_id, occurrences)

  defp stable_item(arguments) do
    case existing_item(arguments) do
      nil
      when not is_nil(arguments.item_id) and not is_map_key(arguments, :candidate_record_id) ->
        {:error, :item_not_found}

      nil ->
        create_item(arguments)

      item ->
        {:ok, item}
    end
  end

  defp existing_item(%{item_id: item_id} = arguments) when not is_nil(item_id) do
    Datasets.get_item_internal!(
      query: [
        filter: [
          id: item_id,
          dataset_id: arguments.dataset_id,
          organization_id: arguments.organization_id
        ],
        lock: :for_update
      ],
      authorize?: false
    )
  end

  defp existing_item(arguments) do
    Datasets.get_item_internal!(
      query: [
        filter: [
          dataset_id: arguments.dataset_id,
          organization_id: arguments.organization_id,
          external_key: arguments.external_key
        ],
        lock: :for_update
      ],
      authorize?: false
    )
  end

  defp create_item(arguments) do
    attributes = %{
      organization_id: arguments.organization_id,
      dataset_id: arguments.dataset_id,
      external_key: arguments.external_key
    }

    attributes =
      if arguments.item_id, do: Map.put(attributes, :id, arguments.item_id), else: attributes

    DatasetItem
    |> Ash.Changeset.for_create(:create_internal, attributes)
    |> Ash.create(authorize?: false)
  end

  defp matching_identity(item, %{external_key: nil}),
    do: if(item.external_key, do: {:error, :item_identity_conflict}, else: :ok)

  defp matching_identity(item, arguments) do
    if item.external_key == arguments.external_key,
      do: :ok,
      else: {:error, :item_identity_conflict}
  end

  defp latest_revision(item_id) do
    DatasetItemRevision
    |> Ash.Query.filter(item_id == ^item_id)
    |> Ash.Query.sort(revision_number: :desc, id: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read_one!(authorize?: false)
  end

  defp create_revision!(arguments, schema, item, latest, occurrences, fingerprint) do
    record_id =
      arguments[:candidate_record_id] ||
        QuickTrain.Datasets.construct_record!(
          arguments.organization_id,
          arguments.dataset_id,
          schema.id,
          schema.root_record_type_id,
          occurrences,
          authorize?: false
        ).id

    DatasetItemRevision
    |> Ash.Changeset.for_create(:create_internal, %{
      organization_id: arguments.organization_id,
      dataset_id: arguments.dataset_id,
      item_id: item.id,
      schema_version_id: schema.id,
      root_record_type_id: schema.root_record_type_id,
      root_record_id: record_id,
      revision_number: if(latest, do: latest.revision_number + 1, else: 1),
      fingerprint: fingerprint
    })
    |> Ash.create!(authorize?: false)
  end
end
