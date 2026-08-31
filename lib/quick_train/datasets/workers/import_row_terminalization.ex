defmodule QuickTrain.Datasets.Workers.ImportRowTerminalization do
  # Each terminal Oban row is reduced through an explicit fail-fast reconciliation branch.
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting
  @moduledoc false

  use Oban.Worker,
    queue: :dataset_imports,
    max_attempts: 5,
    unique: [
      period: :infinity,
      fields: [:worker],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  import Ecto.Query

  alias QuickTrain.Datasets.DatasetImportRow.Process
  alias QuickTrain.Datasets.Workers.ProcessImportRow

  @page_size 100

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    terminal_jobs =
      Oban.Job
      |> where([job], job.worker == ^inspect(ProcessImportRow))
      |> where([job], job.state in ^["discarded", "cancelled"])
      |> join(:inner, [job], row in "dataset_import_rows",
        on: fragment("CAST(? AS text) = ?->>'row_id'", field(row, :id), job.args)
      )
      |> where([_job, row], field(row, :outcome) == "pending")
      |> order_by([job], asc: job.id)
      |> limit(@page_size)
      |> QuickTrain.Repo.all()

    Enum.reduce_while(terminal_jobs, :ok, fn job, :ok ->
      case job.args do
        %{"row_id" => row_id} ->
          case Process.terminalize(row_id) do
            {:ok, _status} -> {:cont, :ok}
            {:error, error} -> {:halt, {:error, error}}
          end

        _other ->
          {:cont, :ok}
      end
    end)
  end
end
