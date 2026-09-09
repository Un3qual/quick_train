defmodule QuickTrain.Datasets.DatasetImportRow.Actions.Append do
  # The nested branch mirrors the import-lock lifecycle and rollback decisions.
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting
  @moduledoc false

  alias QuickTrain.DatasetAssetError

  use Ash.Resource.Actions.Implementation

  require Ash.Query

  alias QuickTrain.Datasets.{
    DatasetImport,
    DatasetImportRow,
    DatasetSchemaVersion,
    Fingerprint
  }

  alias QuickTrain.Datasets.DatasetImportRow.Structure
  alias QuickTrain.Datasets.DatasetRecord.Values

  @impl true
  def run(input, _opts, _context) do
    arguments = Map.put_new(input.arguments, :external_key, nil)

    case Structure.validate(arguments) do
      {:ok, entries} ->
        Ash.transact(import_resources(), fn -> append_locked(arguments, entries) end)

      {:error, reason} ->
        DatasetAssetError.wrap({:error, reason})
    end
  end

  defp append_locked(arguments, entries) do
    case locked_import(arguments.organization_id, arguments.import_id) do
      nil ->
        DatasetAssetError.invalid(:invalid_import)

      %{phase: :sealed} ->
        DatasetAssetError.invalid(:import_not_open)

      import ->
        if DateTime.compare(import.open_expires_at, DateTime.utc_now()) != :gt do
          DatasetAssetError.invalid(:import_expired)
        else
          schema = published_schema(import)

          if schema do
            fingerprint =
              Fingerprint.import_row(
                import.schema_version_id,
                arguments.row_key,
                arguments.external_key,
                arguments.source_position,
                entries
              )

            accept_or_retry(import, schema, arguments, entries, fingerprint)
          else
            DatasetAssetError.invalid(:invalid_schema)
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
        DatasetAssetError.invalid(:idempotency_conflict)

      row_by(import.id, :source_position, arguments.source_position) ->
        DatasetAssetError.invalid(:idempotency_conflict)

      arguments.external_key && row_by(import.id, :external_key, arguments.external_key) ->
        DatasetAssetError.invalid(:duplicate_external_key)

      Ash.count!(Ash.Query.filter(DatasetImportRow, import_id == ^import.id), authorize?: false) >=
          Application.fetch_env!(:quick_train, :dataset_imports)[:max_rows_per_import] ->
        DatasetAssetError.invalid(:import_row_limit_exceeded)

      true ->
        persist_row(import, schema, arguments, entries, fingerprint)
    end
  end

  defp persist_row(import, schema, arguments, entries, fingerprint) do
    candidate =
      with {:ok, occurrences} <- Values.bind(schema, entries),
           :ok <- Values.validate_assets(import.organization_id, occurrences) do
        {:ok,
         QuickTrain.Datasets.construct_record!(
           import.organization_id,
           import.dataset_id,
           schema.id,
           schema.root_record_type_id,
           occurrences,
           authorize?: false
         )}
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

  defp row_by(import_id, field, value) do
    filter = [{:import_id, import_id}, {field, value}]

    DatasetImportRow
    |> Ash.Query.filter(^filter)
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
      QuickTrain.Datasets.DatasetValue.Text,
      QuickTrain.Datasets.DatasetValue.Integer,
      QuickTrain.Datasets.DatasetValue.Decimal,
      QuickTrain.Datasets.DatasetValue.Boolean,
      QuickTrain.Datasets.DatasetValue.DateTime,
      QuickTrain.Datasets.DatasetValue.Asset,
      QuickTrain.Assets.Asset
    ]
  end
end
