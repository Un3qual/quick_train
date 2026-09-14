defmodule QuickTrain.Tasks.Attempts.OfferedPolicy do
  @moduledoc false
  use Ash.Resource.Calculation
  alias QuickTrain.Projects.ProjectQuestionPolicy
  alias QuickTrain.Tasks.Access.ReadAccess
  alias QuickTrain.Tasks.Attempts.Attempt
  alias QuickTrain.Tasks.Error
  alias QuickTrain.Tasks.Responses.QuestionResponse
  require Ash.Query

  def load(_query, _opts, _context),
    do: [:attempt_id, :project_id, :organization_id, :question_id]

  def calculate(records, opts, context) do
    authorize!(records, context.actor, opts[:field] != :review_status)

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
      attempt_id in ^Enum.map(records, & &1.attempt_id) and
        question_id in ^Enum.map(records, & &1.question_id) and
        attempt.state == :submitted
    )
    |> Ash.Query.load([:effective_verdict])
    |> Ash.read!(authorize?: false, page: false)
    |> Map.new(&{{&1.attempt_id, &1.question_id}, &1})
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

  defp authorize!(records, %{id: _} = actor, live?) do
    ids = Enum.map(records, & &1.attempt_id) |> Enum.uniq()
    manager = ReadAccess.result_authority(actor)

    worker =
      if live?, do: ReadAccess.live_attempt(actor), else: ReadAccess.eligible_attempt(actor)

    allowed =
      Attempt
      |> Ash.Query.filter(id in ^ids and (^manager or ^worker))
      |> Ash.count!(authorize?: false)

    if allowed != length(ids), do: Error.reject!(:forbidden)
    :ok
  end

  defp authorize!(_records, _actor, _live?), do: Error.reject!(:forbidden)
end
