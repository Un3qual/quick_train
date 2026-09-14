defmodule QuickTrain.Tasks.QuestionReview do
  @moduledoc false
  use Ash.Resource.Actions.Implementation

  alias QuickTrain.Tasks.{
    Access,
    Error,
    Progress,
    QuestionResponse,
    Response,
    ReviewDecision,
    Task
  }

  require Ash.Query

  @impl true
  def run(input, _opts, context) do
    arguments = input.arguments
    project = Access.project!(arguments.organization_id, arguments.project_id)
    Access.manager!(project, context.actor, "tasks.review")
    requests = if input.action.name == :decide, do: [arguments], else: arguments.decisions
    decisions = decide_all!(project, requests, context.actor)
    {:ok, if(input.action.name == :decide, do: hd(decisions), else: decisions)}
  rescue
    error in [Ash.Error.Invalid, Ash.Error.Forbidden, Ash.Error.Unknown, Postgrex.Error] ->
      {:error, error}
  end

  # Submission holds the owner locks and commits these decisions with its evidence.
  def initial_decision!(_project, _task, %{outcome: :skipped}), do: :skipped
  def initial_decision!(%{review_mode: :manual}, _task, %{outcome: :answered}), do: :pending

  def initial_decision!(%{review_mode: :automatic}, _task, %{outcome: :answered} = outcome) do
    create_decision!(outcome, %{origin: :system, verdict: :accept, number: 1})
    :accepted
  end

  def effective_status(%{outcome: :skipped}), do: :skipped

  def effective_status(%{outcome: :answered, effective_decision: decision}),
    do: decision_status(decision)

  defp decide_all!(project, requests, actor) do
    ids = Enum.map(requests, & &1.question_response_id)

    if ids == [] or length(Enum.uniq(ids)) != length(ids),
      do: Error.reject!(:invalid_review_batch)

    initial =
      QuestionResponse
      |> Ash.Query.filter(project_id == ^project.id and id in ^ids)
      |> Ash.read!(authorize?: false, page: false)

    if length(initial) != length(ids), do: Error.reject!(:invalid_question_response)

    tasks =
      lock_records(Task, project.id, Enum.map(initial, & &1.task_id)) |> Map.new(&{&1.id, &1})

    responses =
      lock_records(Response, project.id, Enum.map(initial, & &1.response_id))
      |> Ash.load!(:attempt, authorize?: false)
      |> Map.new(&{&1.id, &1})

    outcomes =
      lock_records(QuestionResponse, project.id, ids)
      |> Ash.load!(:effective_decision, authorize?: false)
      |> Map.new(&{&1.id, &1})

    Access.manager!(project, actor, "tasks.review")

    plans =
      Enum.map(requests, fn request ->
        outcome = Map.fetch!(outcomes, request.question_response_id)
        response = Map.fetch!(responses, outcome.response_id)
        if response.state != :submitted, do: Error.reject!(:response_not_submitted)
        if outcome.outcome == :skipped, do: Error.reject!(:skip_not_reviewable)
        if response.attempt.worker_id == actor.id, do: Error.reject!(:self_review)
        plan!(outcome, request, actor)
      end)

    {decisions, _tasks} =
      Enum.map_reduce(plans, tasks, fn
        {:retry, decision}, tasks ->
          {decision, tasks}

        {:create, outcome, attributes, previous}, tasks ->
          decision = create_decision!(outcome, attributes)
          task = Map.fetch!(tasks, outcome.task_id)
          changes = verdict_change(previous, decision_status(decision))
          task = Progress.change!(project, task, %{outcome.question_id => changes})
          {decision, Map.put(tasks, task.id, task)}
      end)

    decisions
  end

  defp plan!(outcome, request, actor) do
    retry =
      ReviewDecision
      |> Ash.Query.filter(
        question_response_id == ^outcome.id and requester_id == ^actor.id and
          request_key == ^request.request_key
      )
      |> Ash.read_one!(authorize?: false)

    attributes = %{
      origin: :human,
      requester_id: actor.id,
      request_key: request.request_key,
      verdict: request.verdict,
      reason: Map.get(request, :reason),
      predecessor_id: Map.get(request, :expected_predecessor_id)
    }

    if retry do
      unless Map.take(retry, Map.keys(attributes)) == attributes,
        do: Error.reject!(:idempotency_conflict)

      {:retry, retry}
    else
      successor!(outcome, attributes)
    end
  end

  defp successor!(outcome, attributes) do
    current = outcome.effective_decision
    predecessor_id = if current, do: current.id

    if predecessor_id != attributes.predecessor_id,
      do: Error.reject!(:stale_review_decision)

    if (current || attributes.verdict == :reject) &&
         (is_nil(attributes.reason) || String.trim(attributes.reason) == ""),
       do: Error.reject!(:review_reason_required)

    attributes = Map.put(attributes, :number, if(current, do: current.number + 1, else: 1))
    {:create, outcome, attributes, decision_status(current)}
  end

  defp verdict_change(previous, current) do
    %{previous => -1}
    |> Map.update(current, 1, &(&1 + 1))
    |> Map.put(:failures, indicator(current == :rejected) - indicator(previous == :rejected))
  end

  defp indicator(true), do: 1
  defp indicator(false), do: 0
  defp decision_status(nil), do: :pending
  defp decision_status(%{verdict: :accept}), do: :accepted
  defp decision_status(%{verdict: :reject}), do: :rejected

  defp lock_records(resource, project_id, ids) do
    resource
    |> Ash.Query.filter(project_id == ^project_id and id in ^ids)
    |> Ash.Query.sort(id: :asc)
    |> Ash.Query.lock(:for_update)
    |> Ash.read!(authorize?: false, page: false)
  end

  defp create_decision!(outcome, attributes) do
    scope =
      Map.take(outcome, [:organization_id, :project_id, :form_version_id, :task_id, :question_id])

    Ash.create!(
      ReviewDecision,
      Map.merge(attributes, Map.put(scope, :question_response_id, outcome.id)),
      action: :create_internal,
      authorize?: false
    )
  end
end
