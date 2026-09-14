defmodule QuickTrain.Tasks.Attempts.AttemptAllocation do
  @moduledoc false
  use Ash.Resource.Actions.Implementation
  alias QuickTrain.Accounts.User

  alias QuickTrain.Projects.{
    ExplicitGroup,
    ExplicitGroupInput,
    Project,
    ProjectItem,
    ProjectQuestionPolicy,
    ProjectSlotPolicy
  }

  alias QuickTrain.Tasks.{Access, Error, Progress, Task, TaskInput}
  alias QuickTrain.Tasks.Access.WorkerEligibility

  alias QuickTrain.Tasks.Attempts.{
    AllocationResult,
    Attempt,
    AttemptInputPresentation,
    AttemptQuestion,
    Leases,
    TaskSelection
  }

  alias QuickTrain.Tasks.Progress.{TaskItemCoverage, TaskQuestionProgress}
  alias QuickTrain.Tasks.Workers.ExpireAttempt

  require Ash.Query
  import Ash.Expr

  @impl true
  def run(input, _opts, context) do
    Ash.transact([Project, Task, Attempt], fn ->
      allocate(input.arguments, input.action.name, context.actor)
    end)
    |> allocation_result()
  rescue
    error in Postgrex.Error ->
      if error.postgres[:code] in [:lock_not_available, :query_canceled, :deadlock_detected],
        do: {:ok, %AllocationResult{status: :retry_later}},
        else: reraise(error, __STACKTRACE__)

    error in Ash.Error.Invalid ->
      allocation_result({:error, error})
  end

  defp allocation_result({:error, %Ash.Error.Invalid{errors: errors}} = result) do
    if Enum.any?(
         errors,
         &(match?(%Error{category: :retry_later}, &1) or
             match?(%Ash.Error.Invalid.Unavailable{}, &1))
       ),
       do: {:ok, %AllocationResult{status: :retry_later}},
       else: result
  end

  defp allocation_result(result), do: result

  defp allocate(args, operation, actor) do
    project = Access.project!(args.organization_id, args.project_id)
    if operation != :fetch, do: Access.manager!(project, actor, "tasks.assign")
    if operation == :follow_up, do: Access.manager!(project, actor, "tasks.results.read")
    worker_id = if operation == :fetch, do: actor.id, else: args.worker_id
    WorkerEligibility.require!(project, worker_id)

    User
    |> Ash.Query.filter(id == ^worker_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(authorize?: false)

    WorkerEligibility.require!(project, worker_id)
    retry_or_select(project, args, operation, actor, worker_id)
  end

  defp retry_or_select(project, args, operation, actor, worker_id) do
    prior =
      Attempt
      |> Ash.Query.filter(
        project_id == ^project.id and requester_id == ^actor.id and
          request_key == ^args.request_key
      )
      |> Ash.read_one!(authorize?: false)

    if prior do
      unless prior.operation == operation and prior.worker_id == worker_id and
               prior.predecessor_id == Map.get(args, :predecessor_id),
             do: Error.reject!(:idempotency_conflict)

      %AllocationResult{status: :issued, attempt: prior}
    else
      unless project.state == :active, do: Error.reject!(:project_closed)
      select(project, args, operation, actor, worker_id)
    end
  end

  defp select(project, args, operation, actor, worker_id) do
    cutoff = Leases.now!()
    live_states = Leases.live_states()

    live =
      Attempt
      |> Ash.Query.filter(
        project_id == ^project.id and worker_id == ^worker_id and state in ^live_states
      )
      |> Ash.read_one!(authorize?: false)

    if live && DateTime.compare(live.deadline, cutoff) == :gt do
      %AllocationResult{status: :waiting_for_answers}
    else
      select_available(project, args, operation, actor, worker_id, live)
    end
  end

  defp select_available(project, args, operation, actor, worker_id, live) do
    predecessor = if operation == :follow_up, do: predecessor!(project, args)
    query = candidate_tasks(project, worker_id, live, predecessor)
    {scanned_ids, selection, stale_cleared?} = scan_tasks(project, query, live, predecessor)

    cond do
      not stale_cleared? ->
        %AllocationResult{status: :retry_later}

      selection ->
        {task, questions} = selection
        issue!(project, task, questions, args, operation, actor, worker_id)

      predecessor ->
        if predecessor.task_id in scanned_ids,
          do: Error.reject!(:no_capacity),
          else: %AllocationResult{status: :retry_later}

      true ->
        remaining = Ash.Query.filter(query, id not in ^scanned_ids)
        new_selection(project, remaining, args, operation, actor, worker_id)
    end
  end

  defp candidate_tasks(project, worker_id, live, predecessor) do
    query = Task |> Ash.Query.filter(project_id == ^project.id)

    if predecessor do
      ids = [predecessor.task_id, live && live.task_id] |> Enum.reject(&is_nil/1)
      Ash.Query.filter(query, id in ^ids)
    else
      live_states = Leases.live_states()
      stale_task_ids = if live, do: [live.task_id], else: []

      # Overdue reservations must be expired under the Task lock before capacity
      # is decided, including the requesting worker's own stale lease.
      Ash.Query.filter(
        query,
        id in ^stale_task_ids or
          (not exists(attempts, worker_id == ^worker_id) and
             (exists(progress, not attention and accepted + pending + live < target) or
                exists(
                  attempts,
                  state in ^live_states and deadline <= fragment("clock_timestamp()")
                )))
      )
    end
  end

  defp scan_tasks(project, query, live, predecessor) do
    # Read one candidate at a time so independent workers can reserve different
    # Tasks. Stable ordering also covers a stale worker lease on another Task.
    query
    |> Ash.Query.sort(id: :asc)
    |> Ash.Query.lock("FOR UPDATE SKIP LOCKED")
    |> Ash.stream!(authorize?: false, batch_size: 1)
    |> Enum.reduce_while({[], nil, is_nil(live)}, fn task, {seen, chosen, stale_cleared?} ->
      Leases.expire_task!(project, task)
      stale_cleared? = stale_cleared? or (live && live.task_id == task.id)
      chosen = chosen || candidate(task, live, predecessor)
      state = {[task.id | seen], chosen, stale_cleared?}
      if chosen && stale_cleared?, do: {:halt, state}, else: {:cont, state}
    end)
  end

  defp candidate(task, live, predecessor) do
    eligible? =
      if predecessor do
        task.id == predecessor.task_id
      else
        is_nil(live) or task.id != live.task_id
      end

    questions = if eligible?, do: available(task, not is_nil(predecessor)), else: []
    if questions != [], do: {task, questions}
  end

  defp predecessor!(project, args) do
    predecessor =
      Attempt
      |> Ash.Query.filter(id == ^args.predecessor_id and project_id == ^project.id)
      |> Ash.read_one!(authorize?: false)
      |> Access.found!()

    if predecessor.state in Leases.live_states(), do: Error.reject!(:invalid_predecessor)
    predecessor
  end

  defp available(task, follow_up?) do
    task.id
    |> Progress.rows()
    |> Enum.filter(fn row ->
      row.accepted + row.pending + row.live < row.target and (follow_up? or not row.attention)
    end)
  end

  defp new_selection(project, remaining, args, operation, actor, worker_id) do
    if Ash.exists?(remaining, authorize?: false) do
      %AllocationResult{status: :retry_later}
    else
      group = select_new_group(project)

      if group,
        do: issue_group!(project, group, args, operation, actor, worker_id),
        else: no_work(project, worker_id)
    end
  end

  defp select_new_group(%{selection_mode: :explicit} = project) do
    case select_group(project, nil) do
      nil ->
        nil

      {inputs, group_id} = group ->
        # Recheck after the group lock: another issuer may have committed after
        # the selection statement took its snapshot. Never skip an authored group.
        if Ash.exists?(Task,
             query: [filter: [project_id: project.id, explicit_group_id: group_id]],
             authorize?: false
           ),
           do: Error.reject!(:retry_later)

        ids = Enum.map(inputs, & &1.project_item_id)

        query =
          Ash.Query.filter(
            TaskItemCoverage,
            project_id == ^project.id and project_item_id in ^ids
          )

        lock_coverage(query, length(ids))
        group
    end
  end

  defp select_new_group(project) do
    query = Ash.Query.filter(TaskItemCoverage, project_id == ^project.id)
    total = Ash.count!(ProjectItem, query: [filter: [project_id: project.id]], authorize?: false)
    coverage = lock_coverage(query, total)
    select_group(project, coverage)
  end

  defp lock_coverage(query, expected) do
    coverage =
      query
      |> Ash.Query.sort(project_item_id: :asc)
      |> Ash.Query.lock("FOR UPDATE SKIP LOCKED")
      |> Ash.read!(authorize?: false, page: false)

    if length(coverage) != expected, do: Error.reject!(:retry_later)
    coverage
  end

  defp issue_group!(
         project,
         {inputs, explicit_group_id},
         args,
         operation,
         actor,
         worker_id
       ) do
    {key, membership} = TaskSelection.canonical(inputs)

    task =
      Ash.create!(
        Task,
        Map.merge(Access.scope(project), %{
          canonical_key: key,
          canonical_membership: membership,
          explicit_group_id: explicit_group_id
        }),
        action: :create_internal,
        authorize?: false
      )

    create_inputs!(project, task, inputs)
    create_progress!(project, task)
    result = issue!(project, task, available(task, false), args, operation, actor, worker_id)
    ids = Enum.map(inputs, & &1.project_item_id)

    # Coverage rows are already locked in the issuance transaction.
    TaskItemCoverage
    |> Ash.Query.filter(project_id == ^project.id and project_item_id in ^ids)
    |> Ash.bulk_update!(:update_internal, %{},
      strategy: [:atomic],
      transaction: false,
      authorize?: false,
      atomic_update: %{exposures: expr(exposures + 1)}
    )

    result
  end

  defp select_group(%{selection_mode: :balanced} = project, coverage) do
    slots =
      ProjectSlotPolicy
      |> Ash.Query.filter(project_id == ^project.id)
      |> Ash.Query.sort(input_slot_id: :asc)
      |> Ash.read!(authorize?: false, page: false)

    items = Enum.map(coverage, &%{id: &1.project_item_id, coverage: &1.exposures})

    deadline =
      System.monotonic_time(:millisecond) +
        Keyword.get(QuickTrain.Repo.config(), :timeout, 15_000)

    TaskSelection.balanced_groups(slots, items, project.coverage_target)
    |> Enum.find_value(fn group ->
      if System.monotonic_time(:millisecond) >= deadline, do: Error.reject!(:retry_later)
      {key, membership} = TaskSelection.canonical(group)

      existing =
        Task
        |> Ash.Query.filter(project_id == ^project.id and canonical_key == ^key)
        |> Ash.read_one!(authorize?: false)

      if existing && existing.canonical_membership != membership,
        do: Error.reject!(:group_identity_conflict)

      if is_nil(existing), do: {group, nil}
    end)
  end

  defp select_group(%{selection_mode: :explicit} = project, _coverage) do
    group =
      ExplicitGroup
      |> Ash.Query.filter(
        project_id == ^project.id and
          not exists(Task, project_id == parent(project_id) and explicit_group_id == parent(id))
      )
      |> Ash.Query.sort(position: :asc, id: :asc)
      |> Ash.Query.limit(1)
      |> Ash.Query.lock("FOR UPDATE NOWAIT")
      |> Ash.read_one!(authorize?: false)

    if group do
      inputs =
        ExplicitGroupInput
        |> Ash.Query.filter(group_id == ^group.id)
        |> Ash.Query.sort(position: :asc, id: :asc)
        |> Ash.read!(authorize?: false, page: false)

      {inputs, group.id}
    end
  end

  defp create_inputs!(project, task, inputs) do
    items =
      ProjectItem
      |> Ash.Query.filter(id in ^Enum.map(inputs, & &1.project_item_id))
      |> Ash.read!(authorize?: false, page: false)
      |> Map.new(&{&1.id, &1})

    attributes =
      Enum.map(inputs, fn input ->
        item = Map.fetch!(items, input.project_item_id)

        Map.merge(Access.scope(project), %{
          task_id: task.id,
          project_item_id: item.id,
          revision_id: item.revision_id,
          input_slot_id: input.input_slot_id
        })
      end)

    Ash.bulk_create!(attributes, TaskInput, :create_internal,
      authorize?: false,
      transaction: :all,
      stop_on_error?: true
    )
  end

  defp create_progress!(project, task) do
    ProjectQuestionPolicy
    |> Ash.Query.filter(project_id == ^project.id)
    |> Ash.stream!(authorize?: false)
    |> Stream.map(fn policy ->
      Map.merge(Access.scope(project), %{
        task_id: task.id,
        question_id: policy.question_id,
        target: policy.accepted_target,
        failure_threshold: policy.failure_threshold
      })
    end)
    |> Ash.bulk_create!(TaskQuestionProgress, :create_internal,
      authorize?: false,
      transaction: :all,
      stop_on_error?: true
    )
  end

  defp issue!(project, task, questions, args, operation, actor, worker_id) do
    if questions == [], do: Error.reject!(:no_capacity)
    cutoff = Leases.now!()
    project_scope = Access.scope(project)

    attrs =
      Map.merge(project_scope, %{
        task_id: task.id,
        requester_id: actor.id,
        worker_id: worker_id,
        request_key: args.request_key,
        operation: operation,
        predecessor_id: Map.get(args, :predecessor_id),
        state: if(operation == :fetch, do: :claimed, else: :assigned),
        deadline: DateTime.add(cutoff, project.lease_minutes * 60, :second)
      })

    attempt = Ash.create!(Attempt, attrs, action: :create_internal, authorize?: false)
    scope = Map.merge(project_scope, %{task_id: task.id, attempt_id: attempt.id})

    questions
    |> Enum.map(&Map.put(scope, :question_id, &1.question_id))
    |> Ash.bulk_create!(AttemptQuestion, :create_internal,
      authorize?: false,
      transaction: :all,
      stop_on_error?: true
    )

    presentation!(project, task, scope)
    Progress.change!(task, Map.new(questions, &{&1.question_id, %{live: 1}}))

    ExpireAttempt.new(
      Map.take(attempt, [:id, :organization_id, :project_id]),
      scheduled_at: attempt.deadline
    )
    |> Oban.insert!()

    %AllocationResult{status: :issued, attempt: attempt}
  end

  defp presentation!(project, task, scope) do
    inputs =
      TaskInput
      |> Ash.Query.filter(task_id == ^task.id)
      |> Ash.Query.sort(id: :asc)
      |> Ash.read!(authorize?: false, page: false)
      |> authored_order(task)
      |> Enum.group_by(& &1.input_slot_id)

    ProjectSlotPolicy
    |> Ash.Query.filter(project_id == ^project.id)
    |> Ash.read!(authorize?: false, page: false)
    |> Enum.flat_map(fn policy ->
      ordered = Map.fetch!(inputs, policy.input_slot_id)
      ordered = if policy.shuffle, do: Enum.shuffle(ordered), else: ordered

      ordered
      |> Enum.with_index()
      |> Enum.map(fn {input, position} ->
        Map.merge(scope, %{
          task_input_id: input.id,
          input_slot_id: policy.input_slot_id,
          position: position
        })
      end)
    end)
    |> Ash.bulk_create!(AttemptInputPresentation, :create_internal,
      authorize?: false,
      transaction: :all,
      stop_on_error?: true
    )
  end

  defp authored_order(inputs, %{explicit_group_id: nil}), do: inputs

  defp authored_order(inputs, task) do
    positions =
      ExplicitGroupInput
      |> Ash.Query.filter(group_id == ^task.explicit_group_id)
      |> Ash.read!(authorize?: false, page: false)
      |> Map.new(&{{&1.input_slot_id, &1.project_item_id}, &1.position})

    Enum.sort_by(inputs, &Map.fetch!(positions, {&1.input_slot_id, &1.project_item_id}))
  end

  defp no_work(project, worker_id) do
    unworked =
      Task
      |> Ash.Query.filter(
        project_id == ^project.id and not exists(attempts, worker_id == ^worker_id)
      )

    progress = Ash.Query.filter(TaskQuestionProgress, project_id == ^project.id)

    status =
      cond do
        not Ash.exists?(unworked, authorize?: false) ->
          :no_work_for_worker

        Ash.exists?(Ash.Query.filter(progress, live > 0 or pending > 0), authorize?: false) ->
          :waiting_for_answers

        Ash.exists?(Ash.Query.filter(progress, accepted < target), authorize?: false) ->
          :needs_attention

        true ->
          :no_work_for_worker
      end

    %AllocationResult{status: status}
  end
end
