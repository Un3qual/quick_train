defmodule QuickTrain.Tasks.Workers.ExpireAttempt do
  @moduledoc false
  use Oban.Worker, queue: :task_maintenance, max_attempts: 10
  alias QuickTrain.Tasks
  alias QuickTrain.Tasks.Attempts.Attempt

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"id" => id, "project_id" => project_id, "organization_id" => organization_id}
      }) do
    with {:ok, %Attempt{} = attempt} <-
           Tasks.get_attempt_internal(id, project_id, organization_id, authorize?: false),
         {:ok, _attempt} <- Tasks.expire_attempt(attempt, authorize?: false) do
      :ok
    else
      {:ok, nil} -> :ok
      error -> error
    end
  end
end
