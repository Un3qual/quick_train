defmodule QuickTrain.Datasets.DatasetImport.Cleanup do
  # Cleanup keeps lock recheck and graph retirement visibly inside one transaction.
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting
  @moduledoc false

  require Ash.Query

  alias QuickTrain.Datasets.{DatasetImport, DatasetImportRow, DatasetRecord}

  def expired(now, limit) do
    DatasetImport
    |> Ash.Query.filter(phase == :open and open_expires_at <= ^now)
    |> Ash.Query.sort(open_expires_at: :asc, id: :asc)
    |> Ash.Query.limit(limit)
    |> Ash.read(authorize?: false)
  end

  def cleanup(import_id, now) do
    Ash.transact([DatasetImport, DatasetImportRow], fn ->
      case locked_import(import_id) do
        %{phase: :open} = import ->
          if DateTime.compare(import.open_expires_at, now) != :gt do
            rows =
              DatasetImportRow
              |> Ash.Query.filter(import_id == ^import.id)
              |> Ash.read!(authorize?: false)

            Enum.each(rows, fn row ->
              Ash.destroy!(row, action: :destroy_internal, authorize?: false)
              destroy_candidate!(row.candidate_record_id)
            end)

            Ash.destroy!(import, action: :destroy_internal, authorize?: false)
            :deleted
          else
            :skipped
          end

        _other ->
          :skipped
      end
    end)
  end

  defp locked_import(import_id) do
    DatasetImport
    |> Ash.Query.filter(id == ^import_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(authorize?: false)
  end

  defp destroy_candidate!(nil), do: :ok

  defp destroy_candidate!(record_id) do
    case Ash.get(DatasetRecord, record_id, authorize?: false, not_found_error?: false) do
      {:ok, nil} ->
        :ok

      {:ok, record} ->
        record =
          Ash.load!(
            record,
            [
              values: [
                :text_value,
                :integer_value,
                :decimal_value,
                :boolean_value,
                :date_time_value,
                :asset_value
              ]
            ],
            authorize?: false
          )

        Enum.each(record.values, &destroy_value!/1)
        Ash.destroy!(record, action: :destroy_internal, authorize?: false)
        :ok

      {:error, error} ->
        raise error
    end
  end

  defp destroy_value!(value) do
    for child <- [
          value.text_value,
          value.integer_value,
          value.decimal_value,
          value.boolean_value,
          value.date_time_value,
          value.asset_value
        ],
        not is_nil(child) do
      Ash.destroy!(child, action: :destroy_internal, authorize?: false)
    end

    Ash.destroy!(value, action: :destroy_internal, authorize?: false)
  end
end
