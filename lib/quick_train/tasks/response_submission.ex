defmodule QuickTrain.Tasks.ResponseSubmission do
  @moduledoc false
  use Ash.Resource.Actions.Implementation
  alias QuickTrain.Forms.Questions.QuestionDefinition
  alias QuickTrain.Projects.Project

  alias QuickTrain.Tasks.{
    Access,
    AnswerValidation,
    Attempt,
    AttemptQuestion,
    Error,
    Leases,
    Progress,
    QuestionResponse,
    QuestionReview,
    Response,
    ResponseDraft
  }

  require Ash.Query

  @impl true
  def run(input, _opts, context) do
    Ash.transact([Project, Attempt, Response], fn -> submit!(input.arguments, context.actor) end)
  rescue
    error in Ash.Error.Invalid -> {:error, error}
  end

  defp submit!(args, actor) do
    project = Access.project!(args.organization_id, args.project_id)
    {task, attempt} = Access.lock_attempt!(project, args.attempt_id)
    response = Access.response!(attempt)
    Access.owner!(project, attempt, actor, false)

    if response.state == :submitted do
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
        |> Ash.Query.filter(response_id == ^response.id)
        |> Ash.Query.sort(id: :asc)
        |> Ash.Query.lock(:for_update)
        |> Ash.read!(authorize?: false, page: false)

      unless MapSet.new(outcomes, & &1.question_id) == offered,
        do: Error.reject!(:incomplete_response)

      for outcome <- outcomes do
        question = Ash.get!(QuestionDefinition, outcome.question_id, authorize?: false)

        AnswerValidation.validate!(
          project,
          task,
          question,
          ResponseDraft.stored_answer(outcome),
          :submit
        )

        ResponseDraft.skip_policy!(project, question.id, outcome)
      end

      Access.owner!(project, attempt, actor)
      cutoff = Leases.now!()

      Ash.update!(response, %{state: :submitted, submitted_at: cutoff},
        action: :update_internal,
        authorize?: false
      )

      submitted =
        Ash.update!(attempt, %{state: :submitted, terminal_at: cutoff},
          action: :update_internal,
          authorize?: false
        )

      changes =
        Map.new(outcomes, fn outcome ->
          status = QuestionReview.initial_decision!(project, task, outcome)

          {outcome.question_id, submission_delta(status)}
        end)

      Progress.change!(project, task, changes)
      submitted
    end
  end

  defp submission_delta(:accepted), do: %{live: -1, accepted: 1}
  defp submission_delta(:pending), do: %{live: -1, pending: 1}
  defp submission_delta(:skipped), do: %{live: -1, skipped: 1, failures: 1}
end
