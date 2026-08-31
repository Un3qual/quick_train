defmodule QuickTrain.Datasets.DatasetImportRow.Actions.Append do
  # The nested branch mirrors the import-lock lifecycle and rollback decisions.
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  require Ash.Query

  alias QuickTrain.Datasets.{
    DatasetImport,
    DatasetImportRow,
    DatasetSchemaVersion,
    ImportRowFingerprint
  }

  alias QuickTrain.Datasets.DatasetImportRow.Structure
  alias QuickTrain.Datasets.DatasetItemRevision.Actions.Put

  @impl true
  def run(input, _opts, _context) do
    arguments = Map.put_new(input.arguments, :external_key, nil)

    with {:ok, entries} <- Structure.validate(arguments) do
      Ash.transact(import_resources(), fn -> append_locked(arguments, entries) end)
    end
  end

  defp append_locked(arguments, entries) do
    case locked_import(arguments.organization_id, arguments.import_id) do
      nil ->
        {:error, :invalid_import}

      %{phase: :sealed} ->
        {:error, :import_not_open}

      import ->
        if DateTime.compare(import.open_expires_at, DateTime.utc_now()) != :gt do
          {:error, :import_expired}
        else
          schema = published_schema(import)

          if schema do
            fingerprint =
              ImportRowFingerprint.encode(
                import.schema_version_id,
                arguments.row_key,
                arguments.external_key,
                arguments.source_position,
                entries
              )

            accept_or_retry(import, schema, arguments, entries, fingerprint)
          else
            {:error, :invalid_schema}
          end
        end
    end
  end

  defp accept_or_retry(import, schema, arguments, entries, fingerprint) do
    row_by_key = row_by(import.id, :row_key, arguments.row_key)

    cond do
      row_by_key && row_by_key.fingerprint == fingerprint ->
        row_by_key

      row_by_key ->
        {:error, :idempotency_conflict}

      row_by(import.id, :source_position, arguments.source_position) ->
        {:error, :idempotency_conflict}

      arguments.external_key && row_by(import.id, :external_key, arguments.external_key) ->
        {:error, :duplicate_external_key}

      Ash.count!(Ash.Query.filter(DatasetImportRow, import_id == ^import.id), authorize?: false) >=
          Application.fetch_env!(:quick_train, :dataset_imports)[:max_rows_per_import] ->
        {:error, :import_row_limit_exceeded}

      true ->
        persist_row(import, schema, arguments, entries, fingerprint)
    end
  end

  defp persist_row(import, schema, arguments, entries, fingerprint) do
    inputs = Enum.map(entries, & &1.input)

    candidate =
      with {:ok, occurrences} <- Put.normalize(schema, inputs),
           :ok <- Put.validate_assets(import.organization_id, occurrences) do
        {:ok, Put.create_normalized_record!(import, schema, occurrences)}
      else
        {:error, reason} -> {:error, sanitize(reason)}
      end

    attributes = %{
      organization_id: import.organization_id,
      dataset_id: import.dataset_id,
      import_id: import.id,
      schema_version_id: import.schema_version_id,
      root_record_type_id: schema.root_record_type_id,
      row_key: arguments.row_key,
      source_position: arguments.source_position,
      external_key: arguments.external_key,
      fingerprint: fingerprint
    }

    attributes =
      case candidate do
        {:ok, record} ->
          Map.merge(attributes, %{candidate_record_id: record.id, outcome: :pending})

        {:error, error_code} ->
          Map.merge(attributes, %{outcome: :failed, error_code: error_code})
      end

    DatasetImportRow
    |> Ash.Changeset.for_create(:create_internal, attributes)
    |> Ash.create!(authorize?: false)
  end

  defp locked_import(organization_id, import_id) do
    DatasetImport
    |> Ash.Query.filter(id == ^import_id and organization_id == ^organization_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(authorize?: false)
  end

  defp published_schema(import) do
    DatasetSchemaVersion
    |> Ash.Query.filter(
      id == ^import.schema_version_id and dataset_id == ^import.dataset_id and
        state == :published
    )
    |> Ash.Query.load(root_record_type: :field_definitions)
    |> Ash.read_one!(authorize?: false)
  end

  defp row_by(import_id, :row_key, value) do
    DatasetImportRow
    |> Ash.Query.filter(import_id == ^import_id and row_key == ^value)
    |> Ash.read_one!(authorize?: false)
  end

  defp row_by(import_id, :source_position, value) do
    DatasetImportRow
    |> Ash.Query.filter(import_id == ^import_id and source_position == ^value)
    |> Ash.read_one!(authorize?: false)
  end

  defp row_by(import_id, :external_key, value) do
    DatasetImportRow
    |> Ash.Query.filter(import_id == ^import_id and external_key == ^value)
    |> Ash.read_one!(authorize?: false)
  end

  defp sanitize(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp sanitize(reason) when is_binary(reason), do: reason
  defp sanitize(_reason), do: "invalid_value"

  defp import_resources do
    [
      DatasetImport,
      DatasetImportRow,
      DatasetSchemaVersion,
      QuickTrain.Datasets.DatasetRecord,
      QuickTrain.Datasets.DatasetValue,
      QuickTrain.Datasets.DatasetTextValue,
      QuickTrain.Datasets.DatasetIntegerValue,
      QuickTrain.Datasets.DatasetDecimalValue,
      QuickTrain.Datasets.DatasetBooleanValue,
      QuickTrain.Datasets.DatasetDateTimeValue,
      QuickTrain.Datasets.DatasetAssetValue,
      QuickTrain.Assets.Asset
    ]
  end
end
