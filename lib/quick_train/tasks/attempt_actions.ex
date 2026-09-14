defmodule QuickTrain.Tasks.AttemptActions do
  @moduledoc false
  use Ash.Resource.Actions.Implementation
  alias QuickTrain.Projects.Project
  alias QuickTrain.Tasks.{Access, Attempt, Error, Leases}

  @impl true
  def run(input, _opts, context) do
    Ash.transact([Project, Attempt], fn ->
      args = input.arguments
      project = Access.project!(args.organization_id, args.project_id)
      {task, attempt} = Access.lock_attempt!(project, args.attempt_id)

      if input.action.name == :cancel do
        Access.manager!(project, context.actor, "tasks.assign")
      else
        Access.owner!(project, attempt, context.actor, false)
      end

      cutoff = Leases.now!()

      case input.action.name do
        :start -> start!(project, attempt, context.actor, cutoff)
        :release -> Leases.terminate!(project, task, attempt, :released, cutoff)
        :cancel -> Leases.terminate!(project, task, attempt, :cancelled, cutoff)
      end
    end)
  rescue
    error in Ash.Error.Invalid -> {:error, error}
  end

  defp start!(project, attempt, actor, cutoff) do
    Access.owner!(project, attempt, actor)

    case attempt.state do
      :in_progress ->
        attempt

      state when state in [:claimed, :assigned] ->
        Ash.update!(attempt, %{state: :in_progress, started_at: cutoff},
          action: :update_internal,
          authorize?: false
        )

      _ ->
        Error.reject!(:attempt_terminal)
    end
  end
end
