defmodule QuickTrain.Datasets.DatasetImport.Actions.Finalize do
  # Sealing and complete job insertion intentionally share one transaction state machine.
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting
  @moduledoc false

  alias QuickTrain.DatasetAssetError

  use Ash.Resource.Actions.Implementation

  require Ash.Query

  alias QuickTrain.Datasets.{DatasetImport, DatasetImportRow}
  alias QuickTrain.Datasets.Workers.ProcessImportRow

  @impl true
  def run(input, _opts, _context) do
    arguments = input.arguments

    Ash.transact([DatasetImport, DatasetImportRow], fn ->
      case locked_import(arguments.organization_id, arguments.import_id) do
        nil ->
          DatasetAssetError.invalid(:invalid_import)

        %{phase: :sealed} = import ->
          import

        import ->
          if DateTime.compare(import.open_expires_at, DateTime.utc_now()) != :gt do
            DatasetAssetError.invalid(:import_expired)
          else
            seal_and_schedule(import)
          end
      end
    end)
  end

  defp seal_and_schedule(import) do
    pending_rows =
      DatasetImportRow
      |> Ash.Query.filter(import_id == ^import.id and outcome == :pending)
      |> Ash.Query.sort(source_position: :asc, id: :asc)
      |> Ash.read!(authorize?: false)

    sealed =
      import
      |> Ash.Changeset.for_update(:seal_internal, %{sealed_at: DateTime.utc_now()})
      |> Ash.update!(authorize?: false)

    case Enum.reduce_while(pending_rows, :ok, fn row, :ok ->
           case scheduler().enqueue(row.id) do
             {:ok, _job} -> {:cont, :ok}
             {:error, error} -> {:halt, {:error, error}}
           end
         end) do
      :ok -> sealed
      {:error, error} -> {:error, error}
    end
  end

  defp locked_import(organization_id, import_id) do
    DatasetImport
    |> Ash.Query.filter(id == ^import_id and organization_id == ^organization_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(authorize?: false)
  end

  defp scheduler do
    Application.get_env(
      :quick_train,
      :dataset_import_row_scheduler,
      ProcessImportRow
    )
  end
end
