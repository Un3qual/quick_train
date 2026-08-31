defmodule QuickTrain.Datasets.DatasetImport.Cleanup do
  # Cleanup keeps lock recheck and graph retirement visibly inside one transaction.
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting
  @moduledoc false

  require Ash.Query

  alias QuickTrain.Datasets.{DatasetImport, DatasetImportRow}
  alias QuickTrain.Datasets.DatasetImportRow.Candidate

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
              Candidate.destroy!(row.candidate_record_id)
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
end
