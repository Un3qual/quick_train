defmodule QuickTrain.Tasks.TaskResponsesTest do
  use QuickTrain.DataCase, async: false
  alias QuickTrain.{Accounts, ProjectsFixture}
  alias QuickTrain.Tasks.Attempts.Attempt
  alias QuickTrain.Tasks.Responses.QuestionResponse
  alias QuickTrain.Tasks.Task

  setup tags do
    context = ProjectsFixture.context!()
    source = ProjectsFixture.source!(context)

    project =
      ProjectsFixture.active!(context, source,
        audience: :external_users,
        external_access: :open,
        reason_required: Map.get(tags, :reason_required, true)
      )

    worker = Accounts.register_user!("respondent@example.test", "Respondent")

    attempt =
      action!(
        Attempt,
        :fetch,
        %{
          organization_id: context.org.id,
          project_id: project.id,
          request_key: Ash.UUID.generate()
        },
        worker
      ).attempt

    %{context: context, source: source, project: project, worker: worker, attempt: attempt}
  end

  test "draft revisions serialize writes and one immutable submission counts once",
       ctx do
    response = save!(ctx, 0, %{outcome: :answered, family: :integer, integer_value: 4})
    assert response.revision == 1

    assert_raise Ash.Error.Invalid, ~r/stale_response/, fn ->
      save!(ctx, 0, %{outcome: :answered, family: :integer, integer_value: 2})
    end

    submitted = submit!(ctx)
    assert submitted.state == :submitted
    assert submit!(ctx).id == submitted.id
    assert Ash.read_one!(QuestionResponse, authorize?: false).integer_value == 4

    task =
      Ash.get!(Task, ctx.attempt.task_id,
        load: [:submitted_count, :live_count],
        authorize?: false
      )

    assert {task.submitted_count, task.live_count, task.state} == {1, 0, :satisfied}

    assert_raise Ash.Error.Invalid, fn ->
      save!(ctx, 1, %{outcome: :answered, family: :integer, integer_value: 1})
    end

    outcome = Ash.read_one!(QuestionResponse, authorize?: false)

    assert_raise Ash.Error.Invalid, ~r/response_submitted/, fn ->
      Ash.destroy!(outcome, action: :destroy_internal, authorize?: false)
    end
  end

  test "an allowed all-skipped submission counts once and preserves explicit reason",
       ctx do
    save!(ctx, 0, %{outcome: :answered, family: :integer, integer_value: 4})
    save!(ctx, 1, %{outcome: :skipped, family: :integer, reason: "Cannot assess"})
    submit!(ctx)
    outcome = Ash.read_one!(QuestionResponse, authorize?: false)
    assert outcome.outcome == :skipped
    assert is_nil(outcome.integer_value)
    assert outcome.skipped_at

    task =
      Ash.get!(Task, ctx.attempt.task_id,
        load: [:submitted_count, :live_count],
        authorize?: false
      )

    assert {task.submitted_count, task.live_count, task.state} == {1, 0, :satisfied}
  end

  @tag reason_required: false
  test "optional skip reasons preserve omitted, empty, and whitespace values", ctx do
    for {reason, revision} <- Enum.with_index([nil, "", " \t"]) do
      save!(ctx, revision, %{outcome: :skipped, family: :integer, reason: reason})
      assert Ash.read_one!(QuestionResponse, authorize?: false).reason == reason
    end

    assert submit!(ctx).state == :submitted
    assert Ash.read_one!(QuestionResponse, authorize?: false).reason == " \t"
  end

  test "required skip reasons reject omitted, empty, and whitespace values", ctx do
    for reason <- [nil, "", " \t"] do
      assert_raise Ash.Error.Invalid, ~r/skip_reason_required/, fn ->
        save!(ctx, 0, %{outcome: :skipped, family: :integer, reason: reason})
      end
    end

    refute Ash.exists?(QuestionResponse, authorize?: false)
  end

  test "incomplete draft stays editable after a rejected submission", ctx do
    response = save!(ctx, 0, %{outcome: :answered, family: :integer})
    assert_raise Ash.Error.Invalid, fn -> submit!(ctx) end
    assert Ash.get!(Attempt, response.id, authorize?: false).state == :in_progress
    save!(ctx, 1, %{outcome: :answered, family: :integer, integer_value: 3})
    assert submit!(ctx).state == :submitted
  end

  test "question response creates reject mismatched scalar payloads in batches", ctx do
    attempt = Ash.read_one!(Attempt, authorize?: false)

    attrs = %{
      organization_id: ctx.project.organization_id,
      project_id: ctx.project.id,
      form_version_id: ctx.project.form_version_id,
      task_id: ctx.attempt.task_id,
      attempt_id: attempt.id,
      question_id: ctx.source.form.question.id,
      family: :integer,
      outcome: :answered
    }

    for payload <- [
          %{text_value: "wrong family"},
          %{boolean_value: false},
          %{outcome: :skipped, integer_value: 3}
        ] do
      result =
        Ash.bulk_create([Map.merge(attrs, payload)], QuestionResponse, :create_internal,
          authorize?: false,
          return_errors?: true
        )

      assert result.status == :error
    end

    refute Ash.exists?(QuestionResponse, authorize?: false)
  end

  test "saving from a stale attempt record preserves the start time and increments stored revision",
       ctx do
    first = save!(ctx, 0, %{outcome: :answered, family: :integer, integer_value: 4})
    assert first.state == :in_progress
    assert first.started_at
    assert first.deadline == ctx.attempt.deadline

    second = save!(ctx, 1, %{outcome: :answered, family: :integer, integer_value: 3})
    assert second.revision == 2
    assert second.started_at == first.started_at
    assert second.deadline == first.deadline
  end

  defp save!(ctx, revision, answer) do
    QuickTrain.Tasks.save_question!(
      ctx.attempt,
      %{
        question_id: ctx.source.form.question.id,
        expected_revision: revision,
        answer: answer
      },
      actor: ctx.worker
    )
  end

  defp submit!(ctx), do: QuickTrain.Tasks.submit_response!(ctx.attempt, actor: ctx.worker)

  defp action!(resource, action, args, actor),
    do: resource |> Ash.ActionInput.for_action(action, args, actor: actor) |> Ash.run_action!()
end
