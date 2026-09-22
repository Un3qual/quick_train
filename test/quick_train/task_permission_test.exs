defmodule QuickTrain.Tasks.TaskPermissionTest do
  use QuickTrain.DataCase, async: false

  alias QuickTrain.{Accounts, Organizations, Projects, ProjectsFixture, Tasks}

  setup do
    context = ProjectsFixture.context!()
    source = ProjectsFixture.source!(context)

    project =
      ProjectsFixture.active!(context, source, audience: :external_users, external_access: :open)

    worker = Accounts.register_user!("permission-worker@example.test", "Worker")

    attempt =
      Tasks.fetch_work!(context.org.id, project.id, Ash.UUID.generate(), actor: worker).attempt

    %{context: context, project: project, source: source, worker: worker, attempt: attempt}
  end

  test "permission checks admit the eligible external owner and reject other actors", ctx do
    stranger = Accounts.register_user!("permission-stranger@example.test", "Stranger")
    refute Organizations.member?(ctx.context.org.id, ctx.worker.id)

    assert Enum.all?(permissions(ctx, ctx.worker))
    refute Enum.any?(permissions(ctx, stranger))
    refute Enum.any?(permissions(ctx, nil))

    Ash.update!(ctx.worker, %{status: "disabled"}, action: :set_status, authorize?: false)

    refute Enum.any?(permissions(ctx, %{ctx.worker | status: "disabled"}))
    refute Enum.any?(permissions(ctx, ctx.worker))
  end

  test "permission checks reflect current worker eligibility", ctx do
    Projects.set_worker_access!(
      ctx.context.org.id,
      ctx.project.id,
      %{user_id: ctx.worker.id, disposition: :block},
      actor: ctx.context.actor
    )

    refute Enum.any?(permissions(ctx, ctx.worker))
  end

  test "ownership policies preserve terminal release retries and receipt access", ctx do
    released = Tasks.release_attempt!(ctx.attempt, actor: ctx.worker)
    assert Tasks.can_release_attempt?(ctx.worker, released)
    assert Tasks.release_attempt!(released, actor: ctx.worker).id == released.id
    assert receipt_permission?(ctx, ctx.worker)

    assert Tasks.attempt_receipt!(ctx.context.org.id, ctx.project.id, released.id,
             actor: ctx.worker
           ).state == :released

    refute Tasks.can_attempt_receipt?(
             ctx.worker,
             Ash.UUID.generate(),
             ctx.project.id,
             released.id
           )
  end

  defp permissions(ctx, actor) do
    [
      Tasks.can_start_attempt?(actor, ctx.attempt),
      Tasks.can_release_attempt?(actor, ctx.attempt),
      Tasks.can_submit_response?(actor, ctx.attempt),
      Tasks.can_save_question?(actor, ctx.attempt, %{
        question_id: ctx.source.form.question.id,
        expected_revision: 0,
        answer: %{outcome: :answered, family: :integer, integer_value: 4}
      }),
      Tasks.can_work_bundle?(actor, ctx.context.org.id, ctx.project.id, ctx.attempt.id),
      receipt_permission?(ctx, actor)
    ]
  end

  defp receipt_permission?(ctx, actor),
    do: Tasks.can_attempt_receipt?(actor, ctx.context.org.id, ctx.project.id, ctx.attempt.id)
end
