defmodule QuickTrain.Tasks.Workers.ReconcileCoverage do
  @moduledoc false
  use Oban.Worker, queue: :task_maintenance, max_attempts: 8

  alias QuickTrain.Tasks

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"organization_id" => organization_id, "project_id" => project_id}
      }) do
    Tasks.reconcile_coverage(organization_id, project_id, authorize?: false)
  end
end
