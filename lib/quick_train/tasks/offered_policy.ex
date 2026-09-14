defmodule QuickTrain.Tasks.OfferedPolicy do
  @moduledoc false
  use Ash.Resource.Calculation
  alias QuickTrain.Tasks.{Access, Attempt, QuestionResponse, ReviewDecision}
  alias QuickTrain.Projects.ProjectQuestionPolicy
  require Ash.Query

  def load(_query, _opts, _context),
    do: [:attempt_id, :project_id, :organization_id, :question_id]

  def calculate(records, opts, context) do
    Enum.map(records, fn row ->
      project =
        QuickTrain.Projects.Project
        |> Ash.Query.filter(id == ^row.project_id)
        |> Ash.read_one!(authorize?: false)

      if opts[:field] == :review_status do
        authorize_status!(project, row, context.actor)

        outcome =
          QuestionResponse
          |> Ash.Query.filter(
            response.attempt_id == ^row.attempt_id and question_id == ^row.question_id and
              response.state == :submitted
          )
          |> Ash.read_one!(authorize?: false)

        case outcome do
          nil ->
            :unsubmitted

          %{outcome: :skipped} ->
            :skipped

          outcome ->
            decision =
              ReviewDecision
              |> Ash.Query.filter(question_response_id == ^outcome.id)
              |> Ash.Query.sort(number: :desc)
              |> Ash.Query.limit(1)
              |> Ash.read_one!(authorize?: false)

            case decision do
              nil -> :pending
              %{verdict: :accept} -> :accepted
              _ -> :rejected
            end
        end
      else
        attempt = Ash.get!(Attempt, row.attempt_id, authorize?: false)

        authorize!(project, attempt, context.actor, true)

        policy =
          ProjectQuestionPolicy
          |> Ash.Query.filter(project_id == ^row.project_id and question_id == ^row.question_id)
          |> Ash.read_one!(authorize?: false)

        Map.fetch!(policy, opts[:field])
      end
    end)
  end

  defp authorize_status!(project, row, actor) do
    attempt = Ash.get!(Attempt, row.attempt_id, authorize?: false)

    authorize!(project, attempt, actor, false)
  end

  defp authorize!(project, attempt, actor, live?) do
    cond do
      actor &&
          QuickTrain.Authorization.allowed?(
            actor.id,
            project.organization_id,
            "tasks.results.read"
          ) ->
        Access.manager!(project, actor, "tasks.results.read")

      actor && actor.id == attempt.worker_id ->
        Access.owner!(project, attempt, actor, live?)

      true ->
        QuickTrain.Tasks.Error.reject!(:forbidden)
    end
  end
end
