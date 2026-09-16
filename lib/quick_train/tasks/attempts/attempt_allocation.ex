defmodule QuickTrain.Tasks.Attempts.AttemptAllocation do
  @moduledoc false
  use Ash.Resource.Actions.Implementation
  alias QuickTrain.Accounts.User

  alias QuickTrain.Projects.{Project, ProjectSlotPolicy}

  alias QuickTrain.Tasks.{Access, Error, Task, TaskInput}
  alias QuickTrain.Tasks.Access.WorkerEligibility

  alias QuickTrain.Tasks.Attempts.{
    AllocationResult,
    Attempt,
    Leases
  }

  alias QuickTrain.Tasks.Workers.ExpireAttempt

  require Ash.Query

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
      unless prior.operation == operation and prior.worker_id == worker_id,
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
    query = candidate_tasks(project, worker_id, live)
    {scanned_ids, selection, stale_cleared?} = scan_tasks(project, query, live)

    cond do
      not stale_cleared? ->
        %AllocationResult{status: :retry_later}

      selection ->
        issue!(project, selection, args, operation, actor, worker_id)

      true ->
        remaining = Ash.Query.filter(query, id not in ^scanned_ids)
        new_selection(project, remaining, args, operation, actor, worker_id)
    end
  end

  defp candidate_tasks(project, worker_id, live) do
    stale_ids = if live, do: [live.task_id], else: []
    live_states = Leases.live_states()

    Task
    |> Ash.Query.filter(
      project_id == ^project.id and exists(attempts, true) and
        (id in ^stale_ids or
           (not exists(attempts, worker_id == ^worker_id) and
              submitted_count < ^project.submission_target and
              (submitted_count + live_count < ^project.submission_target or
                 exists(
                   attempts,
                   state in ^live_states and deadline <= fragment("clock_timestamp()")
                 ))))
    )
  end

  defp scan_tasks(project, query, live) do
    query
    |> Ash.Query.sort(id: :asc)
    |> Ash.Query.lock("FOR NO KEY UPDATE SKIP LOCKED")
    |> Ash.stream!(authorize?: false, batch_size: 1)
    |> Enum.reduce_while({[], nil, is_nil(live)}, fn task, {seen, chosen, stale_cleared?} ->
      Leases.expire_task!(task)
      stale_cleared? = stale_cleared? or (live && live.task_id == task.id)
      counts = Ash.load!(task, [:submitted_count, :live_count], authorize?: false)

      chosen =
        chosen ||
          if (is_nil(live) or task.id != live.task_id) and
               counts.submitted_count + counts.live_count < project.submission_target,
             do: task

      state = {[task.id | seen], chosen, stale_cleared?}
      if chosen && stale_cleared?, do: {:halt, state}, else: {:cont, state}
    end)
  end

  defp new_selection(project, remaining, args, operation, actor, worker_id) do
    if Ash.exists?(remaining, authorize?: false) do
      %AllocationResult{status: :retry_later}
    else
      task = select_unissued_task(project)

      if task,
        do: issue!(project, task, args, operation, actor, worker_id),
        else: no_work(project, worker_id)
    end
  end

  defp select_unissued_task(project) do
    task =
      Task
      |> Ash.Query.filter(project_id == ^project.id and not exists(attempts, true))
      |> Ash.Query.sort(position: :asc, id: :asc)
      |> Ash.Query.limit(1)
      |> Ash.Query.lock("FOR NO KEY UPDATE NOWAIT")
      |> Ash.read_one!(authorize?: false)

    if task && Ash.exists?(Attempt, query: [filter: [task_id: task.id]], authorize?: false),
      do: Error.reject!(:retry_later)

    task
  end

  defp issue!(project, task, args, operation, actor, worker_id) do
    cutoff = Leases.now!()
    project_scope = Access.scope(project)

    attrs =
      Map.merge(project_scope, %{
        task_id: task.id,
        requester_id: actor.id,
        worker_id: worker_id,
        request_key: args.request_key,
        operation: operation,
        state: if(operation == :fetch, do: :claimed, else: :assigned),
        deadline: DateTime.add(cutoff, project.lease_minutes * 60, :second)
      })

    scope = Map.put(project_scope, :task_id, task.id)

    attempt =
      Attempt
      |> Ash.Changeset.for_create(:create_internal, attrs, authorize?: false)
      |> Ash.Changeset.manage_relationship(
        :input_presentations,
        presentation(project, task, scope),
        type: :create,
        on_no_match: {:create, :create_internal},
        authorize?: false,
        bulk?: true
      )
      |> Ash.create!()

    ExpireAttempt.new(
      Map.take(attempt, [:id, :organization_id, :project_id]),
      scheduled_at: attempt.deadline
    )
    |> Oban.insert!()

    %AllocationResult{status: :issued, attempt: attempt}
  end

  defp presentation(project, task, scope) do
    inputs =
      TaskInput
      |> Ash.Query.filter(task_id == ^task.id)
      |> Ash.Query.sort(position: :asc, id: :asc)
      |> Ash.read!(authorize?: false, page: false)
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
  end

  defp no_work(project, worker_id) do
    unworked =
      Task
      |> Ash.Query.filter(
        project_id == ^project.id and not exists(attempts, worker_id == ^worker_id)
      )

    waiting =
      Ash.Query.filter(unworked, submitted_count < ^project.submission_target and live_count > 0)

    status =
      if Ash.exists?(waiting, authorize?: false),
        do: :waiting_for_answers,
        else: :no_work_for_worker

    %AllocationResult{status: status}
  end
end
