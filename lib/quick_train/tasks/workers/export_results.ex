defmodule QuickTrain.Tasks.Workers.ExportResults do
  alias QuickTrain.Tasks.Exports.ResultExporting
  @moduledoc false
  use Oban.Worker,
    queue: :task_exports,
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
