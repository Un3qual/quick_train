defmodule QuickTrain.Tasks.Workers.ExpireAttempt do
  @moduledoc false
  use Oban.Worker, queue: :task_maintenance, max_attempts: 10
  alias QuickTrain.Tasks

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"id" => id, "project_id" => project_id, "organization_id" => organization_id}
      }) do
    with {:ok, attempt} <-
           Tasks.get_attempt_internal(id, project_id, organization_id, authorize?: false),
         {:ok, _attempt} <- Tasks.expire_attempt(attempt, authorize?: false) do
      :ok
    end
  end
end
