defmodule QuickTrain.Tasks.Attempts.ProjectCompletion do
  @moduledoc false
  alias QuickTrain.Tasks.Attempts.{Attempt, Leases}
  import Ash.Expr
  require Ash.Query

  def complete!(project, cutoff) do
    live = Leases.live_states()

    Attempt
    |> Ash.Query.filter(project_id == ^project.id and state in ^live)
    |> Ash.bulk_update!(:update_internal, %{terminal_at: cutoff},
      atomic_update: %{
        state: expr(if deadline <= ^cutoff, do: :expired, else: :cancelled)
      },
      strategy: [:atomic],
      authorize?: false
    )

    :ok
  end
end
