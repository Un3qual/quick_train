defmodule QuickTrain.Tasks.Leases do
  @moduledoc false
  alias QuickTrain.Tasks.{Attempt, AttemptQuestion, Progress}
  require Ash.Query
  @live [:claimed, :assigned, :in_progress]
  def live_states, do: @live

  # PostgreSQL transaction timestamps do not advance while waiting on a lock.
  def now! do
    %{rows: [[now]]} = QuickTrain.Repo.query!("SELECT clock_timestamp()")
    now
  end

  def expire_task!(project, task, cutoff \\ now!()) do
    Attempt
    |> Ash.Query.filter(task_id == ^task.id and state in ^@live and deadline <= ^cutoff)
    |> Ash.Query.sort(id: :asc)
    |> Ash.Query.lock(:for_update)
    |> Ash.read!(authorize?: false, page: false)
    |> Enum.each(&terminate!(project, task, &1, :expired, cutoff))
  end

  def terminate!(project, task, attempt, target, cutoff \\ now!()) do
    if attempt.state in @live do
      state = if DateTime.compare(attempt.deadline, cutoff) != :gt, do: :expired, else: target

      result =
        Ash.update!(attempt, %{state: state, terminal_at: cutoff},
          action: :update_internal,
          authorize?: false
        )

      changes =
        AttemptQuestion
        |> Ash.Query.filter(attempt_id == ^attempt.id)
        |> Ash.read!(authorize?: false, page: false)
        |> Map.new(
          &{&1.question_id,
           %{live: -1, failures: if(state in [:expired, :released], do: 1, else: 0)}}
        )

      Progress.change!(project, task, changes)
      result
    else
      attempt
    end
  end
end
