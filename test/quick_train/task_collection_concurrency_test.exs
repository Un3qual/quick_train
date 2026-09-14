defmodule QuickTrain.Tasks.CollectionConcurrencyTest do
  use QuickTrain.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Elixir.Task, as: AsyncTask
  alias QuickTrain.{Accounts, ProjectsFixture}
  alias QuickTrain.Projects.Project
  alias QuickTrain.Tasks.{Access, Task, TaskInput}
  alias QuickTrain.Tasks.Attempts.Attempt
  alias QuickTrain.Tasks.Progress.{TaskItemCoverage, TaskQuestionProgress}
  alias QuickTrain.Tasks.Responses.{QuestionResponse, Response}
  alias QuickTrain.Tasks.Reviews.ReviewDecision
  alias QuickTrain.Tasks.Workers.ExpireAttempt

  @moduletag :committed_db

  setup tags do
    context =
      ProjectsFixture.context!(
        ~w(projects.read projects.manage forms.read forms.manage datasets.read datasets.manage tasks.assign tasks.results.read)
      )

    source = ProjectsFixture.source!(context, item_count: tags[:item_count] || 1)

    project =
      ProjectsFixture.configured!(context, source,
        selection_mode: tags[:selection_mode] || :balanced,
        audience: :external_users,
        external_access: :open
      )

    if tags[:selection_mode] == :explicit do
      [item] = ProjectsFixture.items(project)

      QuickTrain.Projects.create_explicit_group!(
        context.org.id,
        project.id,
        %{
          position: 0,
          inputs: [
            %{input_slot_id: source.form.slot.id, project_item_id: item.id, position: 0}
          ]
        },
        actor: context.actor
      )
    end

    if tags[:accepted_target] do
      QuickTrain.Projects.set_question_policy!(
        context.org.id,
        project.id,
        %{
          question_id: source.form.question.id,
          accepted_target: tags.accepted_target,
          skip_allowed: true,
          reason_required: true,
          failure_threshold: 3
        },
        actor: context.actor
      )
    end

    project =
      QuickTrain.Projects.activate_project!(context.org.id, project.id, actor: context.actor)

    worker = Accounts.register_user!("race-worker@example.test", "Worker")
    %{context: context, source: source, project: project, worker: worker}
  end

  test "independent workers cannot both claim the final reservation", ctx do
    other = Accounts.register_user!("race-other@example.test", "Other")

    results =
      concurrently([
        fn -> fetch(ctx, Ash.UUID.generate()) end,
        fn -> fetch(%{ctx | worker: other}, Ash.UUID.generate()) end
      ])

    assert Enum.all?(results, &match?({:ok, _}, &1))
    assert Enum.count(results, &match?({:ok, %{status: :issued}}, &1)) == 1
    assert Ash.count!(Task, authorize?: false) == 1
    assert Ash.count!(TaskInput, authorize?: false) == 1
    assert Ash.count!(Attempt, authorize?: false) == 1
    assert Ash.read_one!(TaskItemCoverage, authorize?: false).exposures == 1
    assert Ash.read_one!(TaskQuestionProgress, authorize?: false).live == 1
  end

  @tag item_count: 2
  test "a lock on completed task history does not prevent issuing remaining cohort work", ctx do
    ctx = issue!(ctx)
    assert {:ok, _} = save(ctx, 0, 3)
    assert {:ok, _} = terminal(ctx, :submit)
    other = Accounts.register_user!("history-next@example.test", "Next")
    parent = self()

    holder =
      on_connection(fn ->
        Ash.transact(Task, fn ->
          task = Ash.get!(Task, ctx.attempt.task_id, authorize?: false, lock: :for_update)
          send(parent, {:history_locked, task.state})
          receive do: (:release -> :ok)
        end)
      end)

    try do
      assert_receive {:history_locked, :satisfied}, 5_000

      assert {:ok, %{status: :issued, attempt: next}} =
               fetch(%{ctx | worker: other}, Ash.UUID.generate())

      assert next.task_id != ctx.attempt.task_id
    after
      send(holder.pid, :release)
      AsyncTask.await(holder, 5_000)
    end
  end

  test "simultaneous identical request keys return one fixed attempt", ctx do
    key = Ash.UUID.generate()
    [first, second] = concurrently([fn -> fetch(ctx, key) end, fn -> fetch(ctx, key) end])
    assert {:ok, %{status: :issued, attempt: first}} = first
    assert {:ok, %{status: :issued, attempt: second}} = second
    assert first.id == second.id
    assert first.deadline == second.deadline
    assert Ash.count!(Attempt, authorize?: false) == 1
    assert Ash.count!(Task, authorize?: false) == 1
    assert Ash.read_one!(TaskItemCoverage, authorize?: false).exposures == 1
  end

  @tag accepted_target: 2
  test "an existing task's last slot is reserved only once without inflating item coverage",
       ctx do
    ctx = issue!(ctx)
    first = Accounts.register_user!("next-first@example.test", "Next")
    second = Accounts.register_user!("next-second@example.test", "Next")

    results =
      concurrently([
        fn -> fetch(%{ctx | worker: first}, Ash.UUID.generate()) end,
        fn -> fetch(%{ctx | worker: second}, Ash.UUID.generate()) end
      ])

    assert Enum.all?(results, &match?({:ok, _}, &1))

    assert [{:ok, %{attempt: issued}}] =
             Enum.filter(results, &match?({:ok, %{status: :issued}}, &1))

    assert issued.task_id == ctx.attempt.task_id
    assert Ash.count!(Task, authorize?: false) == 1
    assert Ash.count!(Attempt, authorize?: false) == 2
    assert Ash.read_one!(TaskQuestionProgress, authorize?: false).live == 2
    assert Ash.read_one!(TaskItemCoverage, authorize?: false).exposures == 1
  end

  test "concurrent saves with one expected revision preserve only the successful replacement",
       ctx do
    ctx = issue!(ctx)
    results = concurrently([fn -> save(ctx, 0, 2) end, fn -> save(ctx, 0, 4) end])
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, _}, &1)) == 1
    [{_, response}] = Enum.filter(results, &match?({:ok, _}, &1))
    [{:error, error}] = Enum.filter(results, &match?({:error, _}, &1))
    assert Exception.message(error) =~ "stale_response"
    assert response.revision == 1
    assert Ash.read_one!(Response, authorize?: false).revision == 1
    assert Ash.count!(QuestionResponse, authorize?: false) == 1
    expected = if match?([{:ok, _}, _], results), do: 2, else: 4
    assert Ash.read_one!(QuestionResponse, authorize?: false).integer_value == expected
  end

  for terminal <- [:submit, :release, :cancel, :complete],
      order <- [:save_first, :terminal_first] do
    @tag terminal: terminal, order: order
    test "save and #{terminal} preserve evidence when #{order}", ctx do
      ctx = issue!(ctx)
      assert {:ok, _} = save(ctx, 0, 2)
      save = fn -> save(ctx, 1, 4) end
      terminal = fn -> terminal(ctx, ctx.terminal) end
      {first, second} = if ctx.order == :save_first, do: {save, terminal}, else: {terminal, save}
      lock = if ctx.terminal == :complete, do: :project, else: :task
      {first_result, second_result} = ordered(ctx, first, second, lock: lock)

      if ctx.order == :save_first do
        assert {:ok, %{revision: 2}} = first_result
        assert {:ok, _} = second_result
      else
        assert {:ok, _} = first_result
        assert {:error, _} = second_result
      end

      expected_value = if ctx.order == :save_first, do: 4, else: 2

      expected_state =
        %{submit: :submitted, release: :released, cancel: :cancelled, complete: :cancelled}[
          ctx.terminal
        ]

      assert Ash.get!(Attempt, ctx.attempt.id, authorize?: false).state == expected_state
      assert Ash.read_one!(QuestionResponse, authorize?: false).integer_value == expected_value
      progress = Ash.read_one!(TaskQuestionProgress, authorize?: false)
      assert progress.live == 0
      assert progress.accepted == if(ctx.terminal == :submit, do: 1, else: 0)
      assert progress.failures == if(ctx.terminal == :release, do: 1, else: 0)
    end
  end

  for operation <- [:save, :submit], order <- [:write_first, :expiry_first] do
    @tag operation: operation, order: order
    test "#{operation} and expiry recheck terminal evidence when #{order}", ctx do
      ctx = issue!(ctx)
      assert {:ok, _} = save(ctx, 0, 2)

      write =
        if ctx.operation == :save,
          do: fn -> save(ctx, 1, 4) end,
          else: fn -> terminal(ctx, :submit) end

      {write_result, expiry_result} =
        if ctx.order == :write_first do
          deadline = DateTime.add(DateTime.utc_now(), 2, :second)
          Ash.Seed.update!(ctx.attempt, %{deadline: deadline})

          ordered(ctx, write, fn -> terminal(ctx, :expire) end,
            before_commit: fn -> wait_until!(deadline) end
          )
        else
          Ash.Seed.update!(ctx.attempt, %{deadline: DateTime.add(DateTime.utc_now(), -1, :second)})

          {expired, written} = ordered(ctx, fn -> terminal(ctx, :expire) end, write)
          {written, expired}
        end

      assert expiry_result == :ok
      submitted? = ctx.operation == :submit and ctx.order == :write_first

      if ctx.order == :write_first,
        do: assert({:ok, _} = write_result),
        else: assert({:error, _} = write_result)

      assert Ash.get!(Attempt, ctx.attempt.id, authorize?: false).state ==
               if(submitted?, do: :submitted, else: :expired)

      progress = Ash.read_one!(TaskQuestionProgress, authorize?: false)
      assert progress.live == 0
      assert progress.accepted == if(submitted?, do: 1, else: 0)
      assert progress.failures == if(submitted?, do: 0, else: 1)
      assert terminal(ctx, :expire) == :ok
      assert Ash.read_one!(TaskQuestionProgress, authorize?: false).failures == progress.failures

      assert Ash.read_one!(QuestionResponse, authorize?: false).integer_value ==
               if(ctx.operation == :save and ctx.order == :write_first, do: 4, else: 2)
    end
  end

  for order <- [:submit_first, :complete_first] do
    @tag order: order
    test "submission and project completion serialize when #{order}", ctx do
      ctx = issue!(ctx)
      assert {:ok, _} = save(ctx, 0, 4)
      submit = fn -> terminal(ctx, :submit) end
      complete = fn -> terminal(ctx, :complete) end

      {first, second} =
        if ctx.order == :submit_first, do: {submit, complete}, else: {complete, submit}

      {first_result, second_result} = ordered(ctx, first, second, lock: :project)
      assert {:ok, _} = first_result

      if ctx.order == :submit_first do
        assert {:ok, %{state: :completed}} = second_result
        assert Ash.get!(Attempt, ctx.attempt.id, authorize?: false).state == :submitted
        assert Ash.read_one!(Task, authorize?: false).state == :satisfied
        assert Ash.count!(ReviewDecision, authorize?: false) == 1
      else
        assert {:error, _} = second_result
        assert Ash.get!(Attempt, ctx.attempt.id, authorize?: false).state == :cancelled
        assert Ash.read_one!(Task, authorize?: false).state == :cancelled
        assert Ash.count!(ReviewDecision, authorize?: false) == 0
      end

      assert Ash.get!(Project, ctx.project.id, authorize?: false).state == :completed
      before = Ash.read_one!(TaskQuestionProgress, authorize?: false)

      assert {:ok, _} =
               QuickTrain.Tasks.reconcile_task(
                 ctx.context.org.id,
                 ctx.project.id,
                 ctx.attempt.task_id,
                 authorize?: false
               )

      after_rebuild = Ash.read_one!(TaskQuestionProgress, authorize?: false)

      assert Map.take(before, [:accepted, :live, :failures]) ==
               Map.take(after_rebuild, [:accepted, :live, :failures])
    end
  end

  for order <- [:submit_first, :reconcile_first] do
    @tag order: order
    test "progress rebuilding retains each submitted outcome exactly once when #{order}", ctx do
      ctx = issue!(ctx)
      assert {:ok, _} = save(ctx, 0, 4)
      submit = fn -> terminal(ctx, :submit) end

      rebuild = fn ->
        QuickTrain.Tasks.reconcile_task(ctx.context.org.id, ctx.project.id, ctx.attempt.task_id,
          authorize?: false
        )
      end

      {first, second} =
        if ctx.order == :submit_first, do: {submit, rebuild}, else: {rebuild, submit}

      assert {{:ok, _}, {:ok, _}} = ordered(ctx, first, second)
      progress = Ash.read_one!(TaskQuestionProgress, authorize?: false)

      assert {progress.accepted, progress.pending, progress.live, progress.failures} ==
               {1, 0, 0, 0}

      assert Ash.count!(ReviewDecision, authorize?: false) == 1
    end
  end

  test "completion classifies deadlines at its post-lock wall-clock cutoff", ctx do
    ctx = issue!(ctx)
    deadline = DateTime.add(DateTime.utc_now(), 2, :second)
    Ash.Seed.update!(ctx.attempt, %{deadline: deadline})

    assert {:holding, {:ok, completed}} =
             ordered(ctx, fn -> :holding end, fn -> terminal(ctx, :complete) end,
               lock: :project,
               before_commit: fn -> wait_until!(deadline) end
             )

    attempt = Ash.get!(Attempt, ctx.attempt.id, authorize?: false)
    assert attempt.state == :expired
    assert attempt.terminal_at == completed.completed_at
    assert DateTime.compare(completed.completed_at, deadline) != :lt
    progress = Ash.read_one!(TaskQuestionProgress, authorize?: false)
    assert {progress.live, progress.failures} == {0, 1}
  end

  for selection_mode <- [:balanced, :explicit] do
    @tag selection_mode: selection_mode
    test "rolled-back #{selection_mode} issuance leaves no task, reservation, or consumed group",
         ctx do
      key = Ash.UUID.generate()

      assert {:error, error} =
               Ash.transact(Project, fn ->
                 assert {:ok, %{status: :issued}} = fetch(ctx, key)
                 assert Ash.count!(Task, authorize?: false) == 1
                 Repo.rollback(:injected_failure)
               end)

      assert Exception.message(error) =~ "injected_failure"

      for resource <- [Task, TaskInput, Attempt, Response, TaskQuestionProgress, TaskItemCoverage],
          do: assert(Ash.count!(resource, authorize?: false) == 0)

      assert %{rows: [[0]]} = Repo.query!("SELECT count(*) FROM oban_jobs")
      assert {:ok, %{status: :issued}} = fetch(ctx, key)
      assert Ash.count!(Task, authorize?: false) == 1
      assert Ash.count!(TaskInput, authorize?: false) == 1
      assert Ash.read_one!(TaskItemCoverage, authorize?: false).exposures == 1
    end
  end

  defp issue!(ctx) do
    assert {:ok, %{status: :issued, attempt: attempt}} = fetch(ctx, Ash.UUID.generate())
    Map.put(ctx, :attempt, attempt)
  end

  defp fetch(ctx, key), do: action(ctx, Attempt, :fetch, %{request_key: key}, ctx.worker)

  defp save(ctx, revision, value) do
    action(
      ctx,
      Response,
      :save_question,
      %{
        attempt_id: ctx.attempt.id,
        question_id: ctx.source.form.question.id,
        expected_revision: revision,
        answer: %{outcome: :answered, family: :integer, integer_value: value}
      },
      ctx.worker
    )
  end

  defp terminal(ctx, :complete),
    do:
      QuickTrain.Projects.complete_project(ctx.context.org.id, ctx.project.id,
        actor: ctx.context.actor
      )

  defp terminal(ctx, :submit),
    do: action(ctx, Response, :submit, %{attempt_id: ctx.attempt.id}, ctx.worker)

  defp terminal(ctx, :expire) do
    ExpireAttempt.perform(%Oban.Job{
      args: %{
        "id" => ctx.attempt.id,
        "organization_id" => ctx.context.org.id,
        "project_id" => ctx.project.id
      }
    })
  end

  defp terminal(ctx, transition) do
    actor = if transition == :cancel, do: ctx.context.actor, else: ctx.worker
    action(ctx, Attempt, transition, %{attempt_id: ctx.attempt.id}, actor)
  end

  defp action(ctx, resource, name, args, actor) do
    resource
    |> Ash.ActionInput.for_action(
      name,
      Map.merge(args, %{
        organization_id: ctx.context.org.id,
        project_id: ctx.project.id
      }),
      actor: actor
    )
    |> Ash.run_action()
  end

  defp ordered(ctx, first, second, opts \\ []) do
    parent = self()

    first_task =
      on_connection(fn ->
        Ash.transact(Project, fn -> hold!(ctx, first, parent, opts) end)
      end)

    first_pid = first_task.pid
    assert_receive {:holding, ^first_pid, first_backend}, 5_000

    second_task =
      on_connection(fn ->
        send(parent, {:waiting, self(), backend_id!()})
        second.()
      end)

    try do
      second_pid = second_task.pid
      assert_receive {:waiting, ^second_pid, second_backend}, 5_000
      assert first_backend != second_backend
      await_blocked!(first_backend, second_backend, System.monotonic_time(:millisecond) + 2_000)
      if opts[:before_commit], do: opts[:before_commit].()
      send(first_pid, :commit)
      assert {:ok, first_result} = AsyncTask.await(first_task, 5_000)
      {first_result, AsyncTask.await(second_task, 5_000)}
    after
      send(first_pid, :commit)
      AsyncTask.shutdown(first_task, :brutal_kill)
      AsyncTask.shutdown(second_task, :brutal_kill)
    end
  end

  defp on_connection(operation),
    do: AsyncTask.async(fn -> Sandbox.unboxed_run(Repo, operation) end)

  defp hold!(ctx, operation, parent, opts) do
    lock = if opts[:lock] == :project, do: "FOR UPDATE", else: "FOR SHARE"
    project = Access.project!(ctx.context.org.id, ctx.project.id, lock)
    if opts[:lock] != :project, do: Access.lock_attempt!(project, ctx.attempt.id)
    result = operation.()
    send(parent, {:holding, self(), backend_id!()})

    receive do
      :commit -> result
    after
      5_000 -> flunk("commit barrier was not released")
    end
  end

  defp backend_id! do
    %{rows: [[id]]} = Repo.query!("SELECT pg_backend_pid()")
    id
  end

  defp await_blocked!(holder, waiter, deadline) do
    %{rows: [[blockers]]} = Repo.query!("SELECT pg_blocking_pids($1)", [waiter])

    cond do
      holder in blockers ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("second connection did not wait on the mutation lock")

      true ->
        Process.sleep(10)
        await_blocked!(holder, waiter, deadline)
    end
  end

  defp wait_until!(deadline) do
    Repo.query!(
      "SELECT pg_sleep(GREATEST(0.0, EXTRACT(EPOCH FROM ($1::timestamptz - clock_timestamp()))))",
      [deadline]
    )
  end
end
