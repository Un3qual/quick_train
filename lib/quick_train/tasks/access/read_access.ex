defmodule QuickTrain.Tasks.Access.ReadAccess do
  @moduledoc false
  use Ash.Policy.FilterCheck
  alias QuickTrain.Authorization.RoleAssignment
  alias QuickTrain.Tasks.Access.WorkerEligibility

  alias QuickTrain.Tasks.Attempts.{Attempt, AttemptInputPresentation}

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

  def filter(
        %{id: _} = actor,
        %{resource: Attempt, query: %{action: %{name: :get_for_update}}},
        _opts
      ),
      do: eligible_attempt(actor)

  def filter(%{id: _} = actor, %{resource: resource, query: query}, _opts) do
    cond do
      not task_relationship?(query) ->
        false

      get_in(query.context, [:shared, :task_results]) ->
        authority = result_authority(actor)
        evidence = evidence_filter(resource)
        expr(^authority and ^evidence)

      true ->
        authorized_filter(resource, actor)
    end
  end

  def filter(_, _, _), do: false

  defp task_relationship?(query) do
    case query.context[:accessing_from] do
      %{source: source} -> String.starts_with?(Atom.to_string(source), "Elixir.QuickTrain.Tasks.")
      _ -> false
    end
  end

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

  def authorized_filter(resource, actor) do
    worker = live_worker_filter(resource, live_attempt(actor))
    authority = result_authority(actor)
    evidence = evidence_filter(resource)
    expr(^worker or (^authority and ^evidence))
  end

  defp live_worker_filter(Task, live), do: expr(exists(Attempt, task_id == parent(id) and ^live))

  defp live_worker_filter(TaskInput, live),
    do: expr(exists(Attempt, task_id == parent(task_id) and ^live))

  defp live_worker_filter(Attempt, live), do: live

  defp live_worker_filter(resource, live)
       when resource in [AttemptInputPresentation],
       do: expr(exists(attempt, ^live))

  defp live_worker_filter(QuestionResponse, live), do: expr(exists(attempt, ^live))

  defp live_worker_filter(resource, live)
       when resource in [StaticOptionAnswer, TaskInputAnswer, TextSpan],
       do: expr(exists(question_response.attempt, ^live))

  defp live_worker_filter(resource, _live)
       when resource in [ReviewDecision], do: false

  def evidence_filter(resource) when resource in [Task, TaskInput], do: true
  def evidence_filter(Attempt), do: expr(state in [:submitted, :expired, :released, :cancelled])

  def evidence_filter(resource) when resource in [AttemptInputPresentation],
    do: expr(attempt.state in [:submitted, :expired, :released, :cancelled])

  def evidence_filter(QuestionResponse), do: expr(attempt.state == :submitted)

  def evidence_filter(resource)
      when resource in [StaticOptionAnswer, TaskInputAnswer, TextSpan, ReviewDecision],
      do: expr(question_response.attempt.state == :submitted)
end
