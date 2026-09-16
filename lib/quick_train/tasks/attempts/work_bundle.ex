defmodule QuickTrain.Tasks.Attempts.WorkBundle do
  @moduledoc false
  use Ash.Resource.Preparation
  alias QuickTrain.Tasks.Access

  @impl true
  def prepare(query, _opts, context),
    do: Ash.Query.before_action(query, &lock_attempt(&1, context.actor))

  defp lock_attempt(query, actor) do
    project = Access.project!(query.arguments.organization_id, query.arguments.project_id)
    Access.lock_attempt!(project, query.arguments.attempt_id)
    Ash.Query.after_action(query, fn _query, attempts -> authorize(attempts, project, actor) end)
  rescue
    error in [Ash.Error.Invalid, Ash.Error.Forbidden] -> Ash.Query.add_error(query, error)
  end

  defp authorize(attempts, project, actor) do
    attempt = attempts |> List.first() |> Access.found!()
    Access.owner!(project, attempt, actor)
    {:ok, attempts}
  rescue
    error in [Ash.Error.Invalid, Ash.Error.Forbidden] -> {:error, error}
  end
end
