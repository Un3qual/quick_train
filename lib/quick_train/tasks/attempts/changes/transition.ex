defmodule QuickTrain.Tasks.Attempts.Changes.Transition do
  @moduledoc false
  use Ash.Resource.Change
  alias QuickTrain.Tasks.Access
  alias QuickTrain.Tasks.Attempts.Leases

  @impl true
  def change(changeset, _opts, context),
    do: Ash.Changeset.before_action(changeset, &transition(&1, context.actor))

  defp transition(changeset, actor) do
    project = Access.project!(changeset.data.organization_id, changeset.data.project_id)
    {_task, attempt} = Access.lock_attempt!(project, changeset.data.id)
    changeset = %{changeset | data: attempt}

    case changeset.action.name do
      :cancel -> Access.manager!(project, actor, "tasks.assign")
      :expire -> :ok
      _ -> Access.owner!(project, attempt, actor, false)
    end

    cutoff = Leases.now!()

    if changeset.action.name == :start do
      Access.owner!(project, attempt, actor)

      if attempt.state == :in_progress,
        do: Ash.Changeset.set_result(changeset, {:ok, attempt}),
        else:
          Ash.Changeset.force_change_attributes(changeset, %{
            state: :in_progress,
            started_at: cutoff
          })
    else
      terminate(changeset, cutoff)
    end
  rescue
    error in [Ash.Error.Invalid, Ash.Error.Forbidden] -> Ash.Changeset.add_error(changeset, error)
  end

  defp terminate(changeset, cutoff) do
    attempt = changeset.data
    expired? = DateTime.compare(attempt.deadline, cutoff) != :gt

    if attempt.state not in Leases.live_states() or
         (changeset.action.name == :expire and not expired?) do
      Ash.Changeset.set_result(changeset, {:ok, attempt})
    else
      state =
        cond do
          expired? -> :expired
          changeset.action.name == :release -> :released
          true -> :cancelled
        end

      changeset
      |> Ash.Changeset.force_change_attributes(%{state: state, terminal_at: cutoff})
    end
  end
end
