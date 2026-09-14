defmodule QuickTrain.Tasks.Responses.ResponseSubmission do
  @moduledoc false
  use Ash.Resource.Actions.Implementation

  alias QuickTrain.Tasks.{Access, Error, Progress}
  alias QuickTrain.Tasks.Attempts.{AttemptQuestion, Leases}
  alias QuickTrain.Tasks.Responses.{AnswerValidation, QuestionResponse, ResponseDraft}
  alias QuickTrain.Tasks.Reviews.QuestionReview

  require Ash.Query

  @impl true
  def run(input, _opts, context) do
    {:ok, submit!(input.arguments, context.actor)}
  rescue
    error in Ash.Error.Invalid -> {:error, error}
  end

  defp submit!(args, actor) do
    project = Access.project!(args.organization_id, args.project_id)
    {task, attempt} = Access.lock_attempt!(project, args.attempt_id)
    Access.owner!(project, attempt, actor, false)

    if attempt.state == :submitted do
      attempt
    else
      Access.owner!(project, attempt, actor)

      offered =
        AttemptQuestion
        |> Ash.Query.filter(attempt_id == ^attempt.id)
        |> Ash.read!(authorize?: false, page: false)
        |> MapSet.new(& &1.question_id)

      outcomes =
        QuestionResponse
        |> Ash.Query.filter(attempt_id == ^attempt.id)
        |> Ash.Query.sort(id: :asc)
        |> Ash.Query.lock(:for_update)
        |> Ash.read!(authorize?: false, page: false)
        |> Ash.load!([:question, :static_options, :input_answers, :text_spans], authorize?: false)

      unless MapSet.new(outcomes, & &1.question_id) == offered,
        do: Error.reject!(:incomplete_response)

      questions =
        outcomes
        |> Enum.filter(&(&1.outcome == :answered))
        |> Enum.map(& &1.question)
        |> AnswerValidation.load_questions!()
        |> Map.new(&{&1.id, &1})

      task =
        if Enum.any?(
             outcomes,
             &(&1.family in [
                 :task_input_single_choice,
                 :task_input_multiple_choice,
                 :task_input_ranking,
                 :text_spans
               ])
           ),
           do: Ash.load!(task, :inputs, authorize?: false),
           else: task

      project =
        if Enum.any?(outcomes, &(&1.family == :text_spans)),
          do: Ash.load!(project, :bindings, authorize?: false),
          else: project

      for outcome <- outcomes do
        question = Map.get(questions, outcome.question_id, outcome.question)

        AnswerValidation.validate!(
          project,
          task,
          question,
          ResponseDraft.stored_answer(outcome),
          :submit
        )
      end

      ResponseDraft.skip_policies!(project, outcomes)

      Access.owner!(project, attempt, actor)
      cutoff = Leases.now!()

      submitted =
        Ash.update!(attempt, %{state: :submitted, terminal_at: cutoff},
          action: :update_internal,
          authorize?: false
        )

      statuses = QuestionReview.initial_decisions!(project, outcomes)

      changes =
        Map.new(outcomes, fn outcome ->
          status = Map.fetch!(statuses, outcome.id)

          {outcome.question_id, submission_delta(status)}
        end)

      Progress.change!(task, changes)
      submitted
    end
  end

  defp submission_delta(:accepted), do: %{live: -1, accepted: 1}
  defp submission_delta(:pending), do: %{live: -1, pending: 1}
  defp submission_delta(:skipped), do: %{live: -1, skipped: 1, failures: 1}
end
