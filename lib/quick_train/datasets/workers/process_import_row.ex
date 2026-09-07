defmodule QuickTrain.Datasets.Workers.ProcessImportRow do
  @moduledoc false

  use Oban.Worker,
    queue: :dataset_imports,
    max_attempts: 8,
    unique: [
      period: :infinity,
      fields: [:worker, :args],
      keys: [:row_id],
      states: [:available, :scheduled, :executing, :retryable, :completed]
    ]

  alias QuickTrain.Datasets

  def enqueue(row_id) do
    %{row_id: row_id}
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"row_id" => row_id}}) do
    case Datasets.process_import_row(row_id, authorize?: false) do
      {:ok, _result} -> :ok
      {:error, error} -> {:error, error}
    end
  end
end
