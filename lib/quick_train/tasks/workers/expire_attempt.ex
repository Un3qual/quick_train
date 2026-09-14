defmodule QuickTrain.Tasks.Workers.ExpireAttempt do
  @moduledoc false
  use Oban.Worker, queue: :task_maintenance, max_attempts: 10
  alias QuickTrain.Tasks

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"id" => id, "project_id" => project_id, "organization_id" => organization_id}
      }) do
    case Tasks.expire_attempt(organization_id, project_id, id, authorize?: false) do
      {:ok, _attempt} -> :ok
      error -> error
    end
  end
end
