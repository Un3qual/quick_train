defmodule QuickTrain.Tasks.Responses.ResponseDraft do
  @moduledoc false
  use Ash.Resource.Actions.Implementation
  alias QuickTrain.Forms.Questions.QuestionDefinition
  alias QuickTrain.Projects.ProjectQuestionPolicy

  alias QuickTrain.Tasks.{Access, Error}
  alias QuickTrain.Tasks.Attempts.AttemptQuestion

  alias QuickTrain.Tasks.Responses.{
    AnswerValidation,
    QuestionResponse,
    StaticOptionAnswer,
    TaskInputAnswer,
    TextSpan
  }

  require Ash.Query

  @impl true
  def run(input, _opts, context) do
    {:ok, save!(input.arguments, context.actor)}
  rescue
    error in Ash.Error.Invalid -> {:error, error}
  end

  defp save!(args, actor) do
    project = Access.project!(args.organization_id, args.project_id)
    {task, attempt} = Access.lock_attempt!(project, args.attempt_id)
    response = Access.response!(attempt)
    Access.owner!(project, attempt, actor)
    if response.state != :draft, do: Error.reject!(:response_submitted)
    if response.revision != args.expected_revision, do: Error.reject!(:stale_response)

    offered =
      AttemptQuestion
      |> Ash.Query.filter(attempt_id == ^attempt.id and question_id == ^args.question_id)
      |> Ash.exists?(authorize?: false)

    unless offered, do: Error.reject!(:question_not_offered)
    question = Ash.get!(QuestionDefinition, args.question_id, authorize?: false)
    normalized = AnswerValidation.validate!(project, task, question, args.answer, :draft)
    skip_policies!(project, [Map.put(normalized.attributes, :question_id, question.id)])
    remove_previous!(response, question.id)
    scope = Map.merge(Access.scope(project), %{task_id: task.id, question_id: question.id})

    outcome =
      Ash.create!(
        QuestionResponse,
        Map.merge(scope, Map.put(normalized.attributes, :response_id, response.id)),
        action: :create_internal,
        authorize?: false
      )

    child_scope = Map.put(scope, :question_response_id, outcome.id)

    for {resource, children} <- [
          {StaticOptionAnswer, Enum.map(normalized.option_ids, &%{option_id: &1})},
          {TaskInputAnswer, normalized.inputs},
          {TextSpan, normalized.spans}
        ] do
      children
      |> Enum.map(&Map.merge(child_scope, &1))
      |> Ash.bulk_create!(resource, :create_internal,
        authorize?: false,
        transaction: :all,
        stop_on_error?: true
      )
    end

    response =
      QuickTrain.Tasks.revise_response!(response, authorize?: false)

    if attempt.state in [:claimed, :assigned],
      do: QuickTrain.Tasks.start_attempt_record!(attempt, actor: actor)

    response
  end

  def skip_policies!(project, outcomes) do
    skipped = Enum.filter(outcomes, &(&1.outcome == :skipped))

    if skipped != [] do
      policies =
        ProjectQuestionPolicy
        |> Ash.Query.filter(
          project_id == ^project.id and question_id in ^Enum.map(skipped, & &1.question_id)
        )
        |> Ash.read!(authorize?: false, page: false)
        |> Map.new(&{&1.question_id, &1})

      Enum.each(skipped, &skip_policy!(Map.get(policies, &1.question_id), &1))
    end
  end

  defp skip_policy!(policy, attrs) do
    unless policy && policy.skip_allowed, do: Error.reject!(:skip_not_allowed)

    if policy.reason_required and (is_nil(attrs.reason) or String.trim(attrs.reason) == ""),
      do: Error.reject!(:skip_reason_required)
  end

  defp remove_previous!(response, question_id) do
    prior =
      QuestionResponse
      |> Ash.Query.filter(response_id == ^response.id and question_id == ^question_id)
      |> Ash.Query.lock(:for_update)
      |> Ash.read_one!(authorize?: false)

    if prior, do: Ash.destroy!(prior, action: :destroy_internal, authorize?: false)
  end

  def stored_answer(outcome) do
    attrs =
      Map.take(outcome, [
        :outcome,
        :family,
        :reason,
        :explanation,
        :text_value,
        :integer_value,
        :decimal_value,
        :boolean_value
      ])

    options =
      outcome.static_options
      |> Enum.map(& &1.option_id)

    inputs =
      outcome.input_answers
      |> Enum.map(&Map.take(&1, [:task_input_id, :position]))

    spans =
      outcome.text_spans
      |> Enum.map(&Map.take(&1, [:task_input_id, :source_value_id, :label_id, :start, :end]))

    Map.merge(attrs, %{option_ids: options, inputs: inputs, spans: spans})
  end
end
