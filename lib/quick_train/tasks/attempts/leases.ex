defmodule QuickTrain.Tasks.Attempts.Leases do
  @moduledoc false
  alias QuickTrain.Tasks.Attempts.Attempt
  require Ash.Query
  @live [:claimed, :assigned, :in_progress]
  def live_states, do: @live

  # PostgreSQL transaction timestamps do not advance while waiting on a lock.
  def now! do
    %{rows: [[now]]} = QuickTrain.Repo.query!("SELECT clock_timestamp()")
    now
  end

  def expire_task!(_project, task, cutoff \\ now!()) do
    Attempt
    |> Ash.Query.filter(task_id == ^task.id and state in ^@live and deadline <= ^cutoff)
    |> Ash.Query.sort(id: :asc)
    |> Ash.Query.lock(:for_update)
    |> Ash.read!(authorize?: false, page: false)
    |> Enum.each(&QuickTrain.Tasks.expire_attempt_record!(&1, authorize?: false))
  end
end
