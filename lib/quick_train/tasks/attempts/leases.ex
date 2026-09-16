defmodule QuickTrain.Tasks.Attempts.Leases do
  @moduledoc false
  alias QuickTrain.Repo
  alias QuickTrain.Tasks.Attempts.Attempt
  require Ash.Query
  @live [:claimed, :assigned, :in_progress]
  def live_states, do: @live

  # PostgreSQL transaction timestamps do not advance while waiting on a lock.
  def now! do
    %{rows: [[now]]} = Repo.query!("SELECT clock_timestamp()")
    now
  end

  def expire_task!(task, cutoff \\ now!()) do
    Attempt
    |> Ash.Query.filter(task_id == ^task.id and state in ^@live and deadline <= ^cutoff)
    |> Ash.bulk_update!(:update_internal, %{state: :expired, terminal_at: cutoff},
      strategy: [:atomic],
      authorize?: false
    )
  end
end
