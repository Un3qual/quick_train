defmodule QuickTrain.Tasks.Workers.ExpireAttempt do
  @moduledoc false
  use Oban.Worker, queue: :task_maintenance, max_attempts: 10
  alias QuickTrain.Projects.Project
  alias QuickTrain.Tasks.Access
  alias QuickTrain.Tasks.Attempts.{Attempt, Leases}

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"id" => id, "project_id" => project_id, "organization_id" => organization_id}
      }) do
    Ash.transact([Project, Attempt], fn ->
      project = Access.project!(organization_id, project_id)
      {task, attempt} = Access.lock_attempt!(project, id)
      cutoff = Leases.now!()

      if attempt.state in Leases.live_states() and
           DateTime.compare(attempt.deadline, cutoff) != :gt do
        Leases.terminate!(project, task, attempt, :expired, cutoff)
      end

      :ok
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, error} -> {:error, error}
    end
  end
end
