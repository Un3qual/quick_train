defmodule QuickTrain.Tasks.Attempts.OfferedPolicy do
  @moduledoc false
  use Ash.Resource.Calculation
  alias QuickTrain.Authorization
  alias QuickTrain.Projects.ProjectQuestionPolicy
  alias QuickTrain.Tasks.{Access, Error}
  alias QuickTrain.Tasks.Responses.QuestionResponse
  require Ash.Query

  def load(_query, _opts, _context),
    do: [:attempt_id, :project_id, :organization_id, :question_id]

  def calculate(records, opts, context) do
    records = Ash.load!(records, [:project, :attempt], authorize?: false)

    records
    |> Enum.uniq_by(& &1.attempt_id)
    |> Enum.each(
      &authorize!(&1.project, &1.attempt, context.actor, opts[:field] != :review_status)
    )

    values = values(records, opts[:field])

    Enum.map(records, fn row ->
      if opts[:field] == :review_status,
        do: review_status(Map.get(values, {row.attempt_id, row.question_id})),
        else: Map.fetch!(values, {row.project_id, row.question_id}) |> Map.fetch!(opts[:field])
    end)
  end

  defp values(records, :review_status) do
    QuestionResponse
    |> Ash.Query.filter(
      response.attempt_id in ^Enum.map(records, & &1.attempt_id) and
        question_id in ^Enum.map(records, & &1.question_id) and
        response.state == :submitted
    )
    |> Ash.Query.load([:effective_verdict, :response])
    |> Ash.read!(authorize?: false, page: false)
    |> Map.new(&{{&1.response.attempt_id, &1.question_id}, &1})
  end

  defp values(records, _field) do
    ProjectQuestionPolicy
    |> Ash.Query.filter(
      project_id in ^Enum.map(records, & &1.project_id) and
        question_id in ^Enum.map(records, & &1.question_id)
    )
    |> Ash.read!(authorize?: false, page: false)
    |> Map.new(&{{&1.project_id, &1.question_id}, &1})
  end

  defp review_status(nil), do: :unsubmitted
  defp review_status(%{outcome: :skipped}), do: :skipped

  defp review_status(%{effective_verdict: nil}), do: :pending
  defp review_status(%{effective_verdict: :accept}), do: :accepted
  defp review_status(%{effective_verdict: :reject}), do: :rejected

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
