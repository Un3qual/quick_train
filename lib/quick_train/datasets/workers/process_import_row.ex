defmodule QuickTrain.Datasets.Workers.ProcessImportRow do
  @moduledoc false

  use Oban.Worker,
    queue: :dataset_imports,
    max_attempts: 8

  alias QuickTrain.Datasets

  def enqueue_batch!(rows) do
    rows
    |> Enum.map(&new(%{row_id: &1.id}))
    |> Oban.insert_all()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"row_id" => row_id}}) do
    Datasets.process_import_row(row_id, authorize?: false)
  end
end
