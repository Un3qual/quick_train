defmodule QuickTrain.Tasks.Reviews.QuestionReview do
  @moduledoc false
  use Ash.Resource.Actions.Implementation

  alias QuickTrain.Tasks.{Access, Error, Progress, Task}
  alias QuickTrain.Tasks.Responses.QuestionResponse
  alias QuickTrain.Tasks.Attempts.Attempt
  alias QuickTrain.Tasks.Reviews.ReviewDecision

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
  def initial_decisions!(project, outcomes) do
    statuses = Map.new(outcomes, &{&1.id, initial_status(project, &1)})

    outcomes
    |> Enum.filter(&(Map.fetch!(statuses, &1.id) == :accepted))
    |> Enum.map(&decision_attributes(&1, %{origin: :system, verdict: :accept, number: 1}))
    |> Ash.bulk_create!(ReviewDecision, :create_internal,
      authorize?: false,
      transaction: :all,
      stop_on_error?: true
    )

    statuses
  end

  defp initial_status(_project, %{outcome: :skipped}), do: :skipped
  defp initial_status(%{review_mode: :manual}, %{outcome: :answered}), do: :pending
  defp initial_status(%{review_mode: :automatic}, %{outcome: :answered}), do: :accepted

  def effective_status(%{outcome: :skipped}), do: :skipped

  def effective_status(%{outcome: :answered, effective_decision: decision}),
    do: decision_status(decision)

  defp decide_all!(project, requests, actor) do
    ids = Enum.map(requests, & &1.question_response_id)

    if length(Enum.uniq(ids)) != length(ids),
      do: Error.reject!(:invalid_review_batch)

    initial =
      QuestionResponse
      |> Ash.Query.filter(project_id == ^project.id and id in ^ids)
      |> Ash.read!(authorize?: false, page: false)

    if length(initial) != length(ids), do: Error.reject!(:invalid_question_response)

    tasks =
      lock_records(Task, project.id, Enum.map(initial, & &1.task_id)) |> Map.new(&{&1.id, &1})

    attempts =
      lock_records(Attempt, project.id, Enum.map(initial, & &1.attempt_id))
      |> Map.new(&{&1.id, &1})

    outcomes =
      lock_records(QuestionResponse, project.id, ids)
      |> Ash.load!(:effective_decision, authorize?: false)
      |> Map.new(&{&1.id, &1})

    Access.manager!(project, actor, "tasks.review")

    retries =
      requests
      |> Enum.chunk_every(100)
      |> Enum.flat_map(fn batch ->
        filter =
          Enum.map(
            batch,
            &[question_response_id: &1.question_response_id, request_key: &1.request_key]
          )

        ReviewDecision
        |> Ash.Query.filter(project_id == ^project.id and requester_id == ^actor.id)
        |> Ash.Query.filter(^[or: filter])
        |> Ash.read!(authorize?: false, page: false)
      end)
      |> Map.new(&{{&1.question_response_id, &1.request_key}, &1})

    plans =
      Enum.map(requests, fn request ->
        outcome = Map.fetch!(outcomes, request.question_response_id)
        attempt = Map.fetch!(attempts, outcome.attempt_id)
        if attempt.state != :submitted, do: Error.reject!(:response_not_submitted)
        if outcome.outcome == :skipped, do: Error.reject!(:skip_not_reviewable)
        if attempt.worker_id == actor.id, do: Error.reject!(:self_review)
        plan!(outcome, request, actor, Map.get(retries, {outcome.id, request.request_key}))
      end)

    created =
      plans
      |> Enum.flat_map(fn
        {:create, outcome, attributes, _previous} -> [decision_attributes(outcome, attributes)]
        {:retry, _decision} -> []
      end)
      |> Ash.bulk_create!(ReviewDecision, :create_internal,
        authorize?: false,
        transaction: :all,
        stop_on_error?: true,
        return_records?: true
      )
      |> Map.fetch!(:records)
      |> Map.new(&{&1.question_response_id, &1})

    {decisions, changes} =
      Enum.map_reduce(plans, %{}, fn
        {:retry, decision}, changes ->
          {decision, changes}

        {:create, outcome, _attributes, previous}, changes ->
          decision = Map.fetch!(created, outcome.id)
          delta = verdict_change(previous, decision_status(decision))
          key = {outcome.task_id, outcome.question_id}

          changes =
            Map.update(changes, key, delta, &Map.merge(&1, delta, fn _, a, b -> a + b end))

          {decision, changes}
      end)

    changes
    |> Enum.group_by(fn {{task_id, _question_id}, _delta} -> task_id end, fn
      {{_task_id, question_id}, delta} -> {question_id, delta}
    end)
    |> Enum.each(fn {task_id, deltas} ->
      Progress.change!(project, Map.fetch!(tasks, task_id), Map.new(deltas))
    end)

    decisions
  end

  defp plan!(outcome, request, actor, retry) do
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

  defp decision_attributes(outcome, attributes) do
    scope =
      Map.take(outcome, [:organization_id, :project_id, :form_version_id, :task_id, :question_id])

    Map.merge(attributes, Map.put(scope, :question_response_id, outcome.id))
  end
end
