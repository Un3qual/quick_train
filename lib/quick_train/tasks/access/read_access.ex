defmodule QuickTrain.Tasks.Access.ReadAccess do
  @moduledoc false
  use Ash.Policy.FilterCheck
  alias QuickTrain.Authorization.RoleAssignment
  alias QuickTrain.Tasks.Access.WorkerEligibility

  alias QuickTrain.Tasks.Attempts.{Attempt, AttemptInputPresentation, AttemptQuestion}
  alias QuickTrain.Tasks.Progress.{TaskItemCoverage, TaskQuestionProgress}

  alias QuickTrain.Tasks.Responses.{
    QuestionResponse,
    StaticOptionAnswer,
    TaskInputAnswer,
    TextSpan
  }

  alias QuickTrain.Tasks.Reviews.ReviewDecision
  alias QuickTrain.Tasks.{Task, TaskInput}

  import Ash.Expr

  def describe(_), do: "current access to issued task evidence"

  def filter(%{id: _} = actor, %{resource: resource, query: query}, _opts) do
    cond do
      query.action.name == :read and not task_relationship?(query) ->
        false

      get_in(query.context, [:shared, :task_result_mode]) in [:accepted, :audit] ->
        authority = result_authority(actor)
        evidence = evidence_filter(resource, query.context.shared.task_result_mode)
        expr(^authority and ^evidence)

      true ->
        authorized_filter(resource, actor, :audit, receipt?(query))
    end
  end

  def filter(_, _, _), do: false

  defp task_relationship?(query) do
    case query.context[:accessing_from] do
      %{source: source} -> String.starts_with?(Atom.to_string(source), "Elixir.QuickTrain.Tasks.")
      _ -> false
    end
  end

  defp receipt?(query),
    do:
      match?(
        %{source: QuickTrain.Tasks.Attempts.Receipt, name: :questions},
        query.context[:accessing_from]
      )

  def eligible_attempt(%{id: id}) do
    eligibility =
      QuickTrain.Projects.Project
      |> Ash.Filter.parse!(WorkerEligibility.project_filter(id))
      |> Ash.Filter.move_to_relationship_path([:project])

    expr(worker_id == ^id and worker.status == "active" and ^eligibility)
  end

  def live_attempt(actor) do
    eligible = eligible_attempt(actor)

    expr(
      ^eligible and state in [:claimed, :assigned, :in_progress] and
        deadline > fragment("clock_timestamp()") and
        project.state in [:active, :paused]
    )
  end

  def result_authority(%{id: id}) do
    expr(
      exists(
        RoleAssignment,
        organization_id == parent(organization_id) and user_id == ^id and
          user.status == "active" and organization.status == "active" and
          exists(role.role_capabilities, capability.key == "tasks.results.read") and
          exists(organization.memberships, user_id == ^id and status == "active")
      )
    )
  end

  def authorized_filter(resource, actor, mode \\ :audit, receipt? \\ false) do
    worker = worker_filter(resource, actor, receipt?)
    authority = result_authority(actor)
    evidence = evidence_filter(resource, mode)
    expr(^worker or (^authority and ^evidence))
  end

  defp worker_filter(AttemptQuestion, actor, true) do
    eligible = eligible_attempt(actor)
    expr(exists(attempt, ^eligible))
  end

  defp worker_filter(resource, actor, _receipt?) do
    live_worker_filter(resource, live_attempt(actor))
  end

  defp live_worker_filter(Task, live), do: expr(exists(Attempt, task_id == parent(id) and ^live))

  defp live_worker_filter(TaskInput, live),
    do: expr(exists(Attempt, task_id == parent(task_id) and ^live))

  defp live_worker_filter(Attempt, live), do: live

  defp live_worker_filter(resource, live)
       when resource in [AttemptQuestion, AttemptInputPresentation],
       do: expr(exists(attempt, ^live))

  defp live_worker_filter(QuestionResponse, live), do: expr(exists(attempt, ^live))

  defp live_worker_filter(resource, live)
       when resource in [StaticOptionAnswer, TaskInputAnswer, TextSpan],
       do: expr(exists(question_response.attempt, ^live))

  defp live_worker_filter(resource, _live)
       when resource in [ReviewDecision, TaskQuestionProgress, TaskItemCoverage], do: false

  def evidence_filter(resource, :accepted) do
    base = audit_filter(resource)
    accepted = accepted_filter(resource)
    expr(^base and ^accepted)
  end

  def evidence_filter(resource, _mode), do: audit_filter(resource)

  defp audit_filter(resource) when resource in [Task, TaskInput, TaskQuestionProgress], do: true
  defp audit_filter(TaskItemCoverage), do: expr(exists(issued_inputs, true))
  defp audit_filter(Attempt), do: expr(state in [:submitted, :expired, :released, :cancelled])

  defp audit_filter(resource) when resource in [AttemptQuestion, AttemptInputPresentation],
    do: expr(attempt.state in [:submitted, :expired, :released, :cancelled])

  defp audit_filter(QuestionResponse), do: expr(attempt.state == :submitted)

  defp audit_filter(resource)
       when resource in [StaticOptionAnswer, TaskInputAnswer, TextSpan, ReviewDecision],
       do: expr(question_response.attempt.state == :submitted)

  defp accepted_filter(Task),
    do: expr(exists(outcomes, attempt.state == :submitted and effective_verdict == :accept))

  defp accepted_filter(resource) when resource in [TaskInput, TaskQuestionProgress],
    do: expr(exists(task.outcomes, attempt.state == :submitted and effective_verdict == :accept))

  defp accepted_filter(TaskItemCoverage),
    do:
      expr(
        exists(
          issued_inputs.task.outcomes,
          attempt.state == :submitted and effective_verdict == :accept
        )
      )

  defp accepted_filter(Attempt), do: expr(exists(outcomes, effective_verdict == :accept))

  defp accepted_filter(resource) when resource in [AttemptQuestion, AttemptInputPresentation],
    do: expr(exists(attempt.outcomes, effective_verdict == :accept))

  defp accepted_filter(QuestionResponse), do: expr(effective_verdict == :accept)

  defp accepted_filter(resource) when resource in [StaticOptionAnswer, TaskInputAnswer, TextSpan],
    do: expr(question_response.effective_verdict == :accept)

  defp accepted_filter(ReviewDecision),
    do:
      expr(
        question_response.effective_verdict == :accept and
          number == question_response.effective_decision_number
      )
end
