defmodule QuickTrain.Tasks.Workers.ReconcileProgress do
  @moduledoc false
  use Oban.Worker, queue: :task_maintenance, max_attempts: 8

  alias QuickTrain.Tasks.Progress

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "organization_id" => organization_id,
          "project_id" => project_id,
          "task_id" => task_id
        }
      }) do
    case Progress.reconcile!(organization_id, project_id, task_id) do
      {:ok, _task} -> :ok
      {:error, error} -> {:error, error}
    end
  end
end
