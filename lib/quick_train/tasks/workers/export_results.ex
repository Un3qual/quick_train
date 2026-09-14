defmodule QuickTrain.Tasks.Workers.ExportResults do
  alias QuickTrain.Tasks.ResultExporting
  @moduledoc false
  use Oban.Worker,
    queue: :task_maintenance,
    max_attempts: 10,
    unique: [
      fields: [:worker, :args],
      keys: [:id],
      states: [:available, :scheduled, :executing, :retryable],
      period: :infinity
    ]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"id" => id}}), do: ResultExporting.process(id)
end
