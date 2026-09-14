defmodule QuickTrain.Tasks.Workers.ReconcileProgress do
  @moduledoc false
  use Oban.Worker, queue: :task_maintenance, max_attempts: 8

  alias QuickTrain.Tasks

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "organization_id" => organization_id,
          "project_id" => project_id,
          "task_id" => task_id
        }
      }) do
    case Tasks.reconcile_task(organization_id, project_id, task_id, authorize?: false) do
      {:ok, _task} -> :ok
      error -> error
    end
  end
end
