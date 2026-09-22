defmodule QuickTrain.Tasks.Responses.Changes.Submit do
  @moduledoc false
  use Ash.Resource.Change

  alias QuickTrain.Forms.Questions.QuestionDefinition
  alias QuickTrain.Tasks.{Access, Error}
  alias QuickTrain.Tasks.Attempts.Leases
  alias QuickTrain.Tasks.Responses.{AnswerValidation, QuestionResponse}
  alias QuickTrain.Tasks.Reviews.QuestionReview

  require Ash.Query

  @impl true
  def change(changeset, _opts, context),
    do: Ash.Changeset.before_action(changeset, &submit(&1, context.actor))

  defp submit(changeset, actor) do
    project = Access.project!(changeset.data.organization_id, changeset.data.project_id)
    {task, attempt} = Access.lock_attempt!(project, changeset.data.id)
    changeset = %{changeset | data: attempt}
    Access.owner!(project, attempt, actor, false)

    if attempt.state == :submitted do
      Ash.Changeset.set_result(changeset, {:ok, attempt})
    else
      Access.owner!(project, attempt, actor)

      offered =
        QuestionDefinition
        |> Ash.Query.filter(version_id == ^project.form_version_id)
        |> Ash.read!(authorize?: false, page: false)
        |> MapSet.new(& &1.id)

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

      spans = Enum.flat_map(outcomes, & &1.text_spans)
      span_sources = AnswerValidation.load_span_sources!(project, task.inputs, spans)

      for outcome <- outcomes do
        question = Map.get(questions, outcome.question_id, outcome.question)

        AnswerValidation.validate!(
          project,
          task,
          question,
          AnswerValidation.stored_answer(outcome),
          :submit,
          span_sources
        )
      end

      AnswerValidation.skip_policies!(project, outcomes)

      Access.owner!(project, attempt, actor)
      cutoff = Leases.now!()

      changeset
      |> Ash.Changeset.force_change_attributes(%{state: :submitted, terminal_at: cutoff})
      |> Ash.Changeset.after_action(fn _changeset, submitted ->
        QuestionReview.initial_decisions!(project, outcomes)
        {:ok, submitted}
      end)
    end
  rescue
    error in [Ash.Error.Invalid, Ash.Error.Forbidden] -> Ash.Changeset.add_error(changeset, error)
  end
end
