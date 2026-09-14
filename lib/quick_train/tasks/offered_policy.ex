defmodule QuickTrain.Tasks.OfferedPolicy do
  @moduledoc false
  use Ash.Resource.Calculation
  alias QuickTrain.Authorization
  alias QuickTrain.Projects.{Project, ProjectQuestionPolicy}
  alias QuickTrain.Tasks.{Access, Attempt, Error, QuestionResponse, ReviewDecision}
  require Ash.Query

  def load(_query, _opts, _context),
    do: [:attempt_id, :project_id, :organization_id, :question_id]

  def calculate(records, opts, context),
    do: Enum.map(records, &value!(&1, opts[:field], context.actor))

  defp value!(row, :review_status, actor) do
    {project, attempt} = scope!(row)
    authorize!(project, attempt, actor, false)

    QuestionResponse
    |> Ash.Query.filter(
      response.attempt_id == ^row.attempt_id and question_id == ^row.question_id and
        response.state == :submitted
    )
    |> Ash.read_one!(authorize?: false)
    |> review_status()
  end

  defp value!(row, field, actor) do
    {project, attempt} = scope!(row)
    authorize!(project, attempt, actor, true)

    ProjectQuestionPolicy
    |> Ash.Query.filter(project_id == ^row.project_id and question_id == ^row.question_id)
    |> Ash.read_one!(authorize?: false)
    |> Map.fetch!(field)
  end

  defp scope!(row) do
    {Ash.get!(Project, row.project_id, authorize?: false),
     Ash.get!(Attempt, row.attempt_id, authorize?: false)}
  end

  defp review_status(nil), do: :unsubmitted
  defp review_status(%{outcome: :skipped}), do: :skipped

  defp review_status(outcome) do
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

  defp authorize!(project, attempt, actor, live?) do
    cond do
      actor && Authorization.allowed?(actor.id, project.organization_id, "tasks.results.read") ->
        Access.manager!(project, actor, "tasks.results.read")

      actor && actor.id == attempt.worker_id ->
        Access.owner!(project, attempt, actor, live?)

      true ->
        Error.reject!(:forbidden)
    end
  end
end
