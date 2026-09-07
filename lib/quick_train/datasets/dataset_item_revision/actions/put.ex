defmodule QuickTrain.Datasets.DatasetItemRevision.Actions.Put do
  # The nested branch is the item-lock transaction's explicit rollback state machine.
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  require Ash.Query

  alias QuickTrain.{AshError, ProductError}

  alias QuickTrain.Datasets.{
    DatasetItem,
    DatasetItemRevision,
    DatasetRecord,
    DatasetSchemaVersion,
    RevisionFingerprint
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
           RevisionFingerprint.encode(schema.id, schema.root_record_type_id, occurrences) do
      put(arguments, schema, occurrences, fingerprint, @attempts)
    else
      nil -> ProductError.invalid(:invalid_schema)
      {:error, reason} -> ProductError.wrap({:error, reason})
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

    if record, do: {:ok, Values.load(record)}, else: ProductError.invalid(:invalid_value)
  end

  defp occurrences(schema, arguments), do: Values.normalize(schema, arguments.values)

  defp published_schema(arguments) do
    DatasetSchemaVersion
    |> Ash.Query.filter(
      id == ^arguments.schema_version_id and
        dataset_id == ^arguments.dataset_id and
        dataset.organization_id == ^arguments.organization_id and
        state == :published
    )
    |> Ash.Query.load(root_record_type: :field_definitions)
    |> Ash.read_one!(authorize?: false)
  end

  defp put(arguments, schema, occurrences, fingerprint, attempts) do
    resources = [DatasetItem, DatasetItemRevision, DatasetRecord]

    result =
      Ash.transact(resources, fn ->
        with {:ok, item} <- stable_item(arguments),
             %{} = item <- locked_item(arguments, item.id),
             :ok <- matching_identity(item, arguments),
             :ok <- Values.validate_assets(arguments.organization_id, occurrences) do
          latest = latest_revision(item.id)

          if latest && latest.fingerprint == fingerprint do
            %RevisionResult{changed: false, item: item, revision: latest}
          else
            revision = create_revision!(arguments, schema, item, latest, occurrences, fingerprint)
            %RevisionResult{changed: true, item: item, revision: revision}
          end
        else
          nil -> ProductError.invalid(:invalid_item)
          {:error, reason} -> ProductError.wrap({:error, reason})
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

  defp stable_item(arguments) do
    case existing_item(arguments) do
      nil -> create_item(arguments)
      item -> {:ok, item}
    end
  end

  defp existing_item(%{item_id: item_id} = arguments) when not is_nil(item_id) do
    DatasetItem
    |> Ash.Query.filter(
      id == ^item_id and dataset_id == ^arguments.dataset_id and
        organization_id == ^arguments.organization_id
    )
    |> Ash.read_one!(authorize?: false)
  end

  defp existing_item(arguments) do
    DatasetItem
    |> Ash.Query.filter(
      dataset_id == ^arguments.dataset_id and organization_id == ^arguments.organization_id and
        external_key == ^arguments.external_key
    )
    |> Ash.read_one!(authorize?: false)
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

  defp locked_item(arguments, item_id) do
    DatasetItem
    |> Ash.Query.filter(
      id == ^item_id and dataset_id == ^arguments.dataset_id and
        organization_id == ^arguments.organization_id
    )
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(authorize?: false)
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
    record =
      QuickTrain.Datasets.construct_record!(
        arguments.organization_id,
        arguments.dataset_id,
        schema.id,
        schema.root_record_type_id,
        occurrences,
        authorize?: false
      )

    DatasetItemRevision
    |> Ash.Changeset.for_create(:create_internal, %{
      organization_id: arguments.organization_id,
      dataset_id: arguments.dataset_id,
      item_id: item.id,
      schema_version_id: schema.id,
      root_record_type_id: schema.root_record_type_id,
      root_record_id: record.id,
      revision_number: if(latest, do: latest.revision_number + 1, else: 1),
      fingerprint: fingerprint
    })
    |> Ash.create!(authorize?: false)
  end
end
