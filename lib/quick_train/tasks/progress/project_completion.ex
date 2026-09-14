defmodule QuickTrain.Tasks.Progress.ProjectCompletion do
  @moduledoc false
  alias QuickTrain.Tasks.Attempts.{Attempt, AttemptQuestion, Leases}
  alias QuickTrain.Tasks.Progress.TaskQuestionProgress
  alias QuickTrain.Tasks.Task
  import Ash.Expr
  require Ash.Query

  # The caller holds the exclusive Project lock and owns this transaction.
  # Only physical live attempts and their projections participate; submitted
  # response and review history are never scanned to close a project.
  def complete!(project, cutoff) do
    live = Leases.live_states()

    released = live_offers(live)
    expired = expired_offers(live, cutoff)

    TaskQuestionProgress
    |> Ash.Query.filter(project_id == ^project.id and live > 0)
    |> Ash.bulk_update!(:update_internal, %{},
      strategy: [:atomic],
      authorize?: false,
      atomic_update: %{
        live: expr(live - ^released),
        failures: expr(failures + ^expired),
        attention: expr(accepted < target and failures + ^expired >= failure_threshold)
      }
    )

    Attempt
    |> Ash.Query.filter(project_id == ^project.id and state in ^live and deadline <= ^cutoff)
    |> Ash.bulk_update!(:update_internal, %{state: :expired, terminal_at: cutoff},
      strategy: [:atomic],
      authorize?: false
    )

    Attempt
    |> Ash.Query.filter(project_id == ^project.id and state in ^live)
    |> Ash.bulk_update!(:update_internal, %{state: :cancelled, terminal_at: cutoff},
      strategy: [:atomic],
      authorize?: false
    )

    Task
    |> Ash.Query.filter(project_id == ^project.id and state != :satisfied)
    |> Ash.bulk_update!(:update_internal, %{state: :cancelled},
      strategy: [:atomic],
      authorize?: false
    )

    :ok
  end

  defp live_offers(live),
    do:
      expr(
        count(AttemptQuestion,
          filter:
            expr(
              task_id == parent(task_id) and question_id == parent(question_id) and
                attempt.state in ^live
            )
        )
      )

  defp expired_offers(live, cutoff),
    do:
      expr(
        count(AttemptQuestion,
          filter:
            expr(
              task_id == parent(task_id) and question_id == parent(question_id) and
                attempt.state in ^live and attempt.deadline <= ^cutoff
            )
        )
      )
end
