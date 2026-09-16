defmodule QuickTrain.Tasks.Attempts.ProjectCompletion do
  @moduledoc false
  alias QuickTrain.Tasks.Attempts.{Attempt, Leases}
  require Ash.Query

  def complete!(project, cutoff) do
    live = Leases.live_states()

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

    :ok
  end
end
