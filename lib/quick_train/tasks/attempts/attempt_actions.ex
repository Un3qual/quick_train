defmodule QuickTrain.Tasks.Attempts.AttemptActions do
  @moduledoc false
  use Ash.Resource.Actions.Implementation
  alias QuickTrain.Tasks
  alias QuickTrain.Tasks.Access

  @impl true
  def run(input, _opts, context) do
    args = input.arguments

    attempt =
      Tasks.get_attempt_internal!(args.attempt_id, args.project_id, args.organization_id,
        authorize?: false
      )
      |> Access.found!()

    case input.action.name do
      :start -> Tasks.start_attempt_record(attempt, scope: context)
      :release -> Tasks.release_attempt_record(attempt, scope: context)
      :cancel -> Tasks.cancel_attempt_record(attempt, scope: context)
      :expire -> Tasks.expire_attempt_record(attempt, authorize?: false)
    end
  rescue
    error in Ash.Error.Invalid -> {:error, error}
  end
end
