defmodule QuickTrain.Tasks.TaskAllocationTest do
  use QuickTrain.DataCase, async: false
  alias QuickTrain.{Accounts, ProjectsFixture}
  alias QuickTrain.Projects.Project
  alias QuickTrain.Tasks.{Attempt, Task, TaskInput, TaskQuestionProgress}
  alias QuickTrain.Tasks.Workers.ExpireAttempt

  setup tags do
    context = ProjectsFixture.context!()
    source = ProjectsFixture.source!(context, item_count: tags[:item_count] || 2)

    project =
      ProjectsFixture.active!(context, source, audience: :external_users, external_access: :open)

    worker = Accounts.register_user!("collector@example.test", "Collector")
    %{context: context, source: source, project: project, worker: worker}
  end

  test "an external account receives only issued evidence and a fixed retry identity", ctx do
    key = Ash.UUID.generate()
    first = fetch(ctx, key)
    assert first.status == :issued
    assert first.attempt.worker_id == ctx.worker.id
    assert first.attempt.state == :claimed
    assert Ash.count!(Task, authorize?: false) == 1
    assert Ash.count!(TaskInput, authorize?: false) == 1
    again = fetch(ctx, key)
    assert again.attempt.id == first.attempt.id
    assert again.attempt.deadline == first.attempt.deadline
    assert Ash.count!(Attempt, authorize?: false) == 1
  end

  test "malformed request keys fail before task or coverage changes", ctx do
    assert {:error, _} =
             Attempt
             |> Ash.ActionInput.for_action(
               :fetch,
               %{
                 organization_id: ctx.context.org.id,
                 project_id: ctx.project.id,
                 request_key: "bad"
               },
               actor: ctx.worker
             )
             |> Ash.run_action()

    assert Ash.count!(Task, authorize?: false) == 0
    assert Ash.count!(Attempt, authorize?: false) == 0
  end

  test "blocking the owner denies allocation retries", ctx do
    key = Ash.UUID.generate()
    fetch(ctx, key)

    ProjectsFixture.run!(ctx.context, ctx.project, :set_worker_access, %{
      user_id: ctx.worker.id,
      disposition: :block
    })

    assert_raise Ash.Error.Invalid, ~r/forbidden/, fn -> fetch(ctx, key) end
  end

  test "completion expires overdue work first and cancels only remaining leases", ctx do
    first = fetch(ctx, Ash.UUID.generate()).attempt
    second_worker = Accounts.register_user!("second@example.test", "Second")
    second = fetch(%{ctx | worker: second_worker}, Ash.UUID.generate()).attempt

    Repo.query!(
      "UPDATE attempts SET deadline = clock_timestamp() - interval '1 second' WHERE id = $1",
      [Ecto.UUID.dump!(first.id)]
    )

    completed = ProjectsFixture.run!(ctx.context, ctx.project, :complete)
    assert completed.state == :completed
    assert Ash.get!(Attempt, first.id, authorize?: false).state == :expired
    assert Ash.get!(Attempt, second.id, authorize?: false).state == :cancelled
    progress = Ash.read!(TaskQuestionProgress, authorize?: false)
    assert Enum.sum(Enum.map(progress, & &1.live)) == 0
    assert Enum.sum(Enum.map(progress, & &1.failures)) == 1
    assert Enum.all?(Ash.read!(Task, authorize?: false), &(&1.state == :cancelled))

    assert ProjectsFixture.run!(ctx.context, ctx.project, :complete).completed_at ==
             completed.completed_at
  end

  test "another worker's overdue lease contributes failure before capacity is reused", ctx do
    first = fetch(ctx, Ash.UUID.generate()).attempt

    Repo.query!(
      "UPDATE attempts SET deadline = clock_timestamp() - interval '1 second' WHERE id = $1",
      [Ecto.UUID.dump!(first.id)]
    )

    second_worker = Accounts.register_user!("next@example.test", "Next")
    next = fetch(%{ctx | worker: second_worker}, Ash.UUID.generate()).attempt
    assert next.task_id == first.task_id
    assert Ash.get!(Attempt, first.id, authorize?: false).state == :expired
    progress = Ash.read_one!(TaskQuestionProgress, authorize?: false)
    assert progress.live == 1
    assert progress.failures == 1

    assert :ok =
             ExpireAttempt.perform(%Oban.Job{
               args: %{
                 "id" => first.id,
                 "organization_id" => first.organization_id,
                 "project_id" => first.project_id
               }
             })

    assert Ash.read_one!(TaskQuestionProgress, authorize?: false).failures == 1
  end

  @tag item_count: 1
  test "personal exhaustion does not prevent another eligible worker from reusing demand", ctx do
    first = fetch(ctx, Ash.UUID.generate()).attempt

    QuickTrain.Tasks.release_attempt!(ctx.context.org.id, ctx.project.id, first.id,
      actor: ctx.worker
    )

    assert fetch(ctx, Ash.UUID.generate()).status == :no_work_for_worker
    other = Accounts.register_user!("fresh@example.test", "Fresh")
    assert fetch(%{ctx | worker: other}, Ash.UUID.generate()).attempt.task_id == first.task_id
    assert Ash.count!(Task, authorize?: false) == 1

    assert Ash.get!(Project, ctx.project.id, authorize?: false).state ==
             :active
  end

  @tag item_count: 1
  test "delayed expiry reaches attention before allocation and cleanup commits on no-work", ctx do
    project =
      ProjectsFixture.configured!(ctx.context, ctx.source,
        audience: :external_users,
        external_access: :open
      )

    ProjectsFixture.run!(ctx.context, project, :set_question_policy, %{
      question_id: ctx.source.form.question.id,
      accepted_target: 1,
      failure_threshold: 1,
      skip_allowed: true,
      reason_required: false
    })

    project = ProjectsFixture.run!(ctx.context, project, :activate)
    ctx = %{ctx | project: project}
    first = fetch(ctx, Ash.UUID.generate()).attempt

    Repo.query!(
      "UPDATE attempts SET deadline = clock_timestamp() - interval '1 second' WHERE id = $1",
      [Ecto.UUID.dump!(first.id)]
    )

    other = Accounts.register_user!("threshold@example.test", "Threshold")
    assert fetch(%{ctx | worker: other}, Ash.UUID.generate()).status == :needs_attention
    assert Ash.get!(Attempt, first.id, authorize?: false).state == :expired
    assert Ash.get!(Task, first.task_id, authorize?: false).state == :needs_attention
    progress = Ash.read_one!(TaskQuestionProgress, authorize?: false)
    assert {progress.live, progress.failures, progress.attention} == {0, 1, true}
  end

  test "member and external routes combine while a block overrides either route", ctx do
    project =
      ProjectsFixture.active!(ctx.context, ctx.source,
        audience: :both,
        external_access: :allowlisted
      )

    ctx = %{ctx | project: project}
    assert_raise Ash.Error.Invalid, ~r/forbidden/, fn -> fetch(ctx, Ash.UUID.generate()) end
    QuickTrain.Organizations.add_member!(ctx.context.org.id, ctx.worker.id)
    first = fetch(ctx, Ash.UUID.generate()).attempt
    assert first.worker_id == ctx.worker.id
    outsider = Accounts.register_user!("allowlisted@example.test", "Outside")

    ProjectsFixture.run!(ctx.context, project, :set_worker_access, %{
      user_id: outsider.id,
      disposition: :allow
    })

    assert fetch(%{ctx | worker: outsider}, Ash.UUID.generate()).status == :issued

    ProjectsFixture.run!(ctx.context, project, :set_worker_access, %{
      user_id: ctx.worker.id,
      disposition: :block
    })

    assert_raise Ash.Error.Invalid, ~r/forbidden/, fn -> fetch(ctx, first.request_key) end
  end

  test "pause permits existing work but prevents a new claim, with fixed start retry timestamps",
       ctx do
    attempt = fetch(ctx, Ash.UUID.generate()).attempt
    ProjectsFixture.run!(ctx.context, ctx.project, :pause)

    started =
      QuickTrain.Tasks.start_attempt!(ctx.context.org.id, ctx.project.id, attempt.id,
        actor: ctx.worker
      )

    assert started.deadline == attempt.deadline

    assert QuickTrain.Tasks.start_attempt!(ctx.context.org.id, ctx.project.id, attempt.id,
             actor: ctx.worker
           ).started_at == started.started_at

    assert_raise Ash.Error.Invalid, ~r/project_closed/, fn -> fetch(ctx, Ash.UUID.generate()) end
    assert fetch(ctx, attempt.request_key).attempt.id == attempt.id

    QuickTrain.Tasks.release_attempt!(ctx.context.org.id, ctx.project.id, attempt.id,
      actor: ctx.worker
    )

    assert Ash.get!(Attempt, attempt.id, authorize?: false).state == :released
  end

  defp fetch(ctx, key) do
    Attempt
    |> Ash.ActionInput.for_action(
      :fetch,
      %{organization_id: ctx.context.org.id, project_id: ctx.project.id, request_key: key},
      actor: ctx.worker
    )
    |> Ash.run_action!()
  end
end
