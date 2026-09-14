defmodule QuickTrain.Tasks.TaskResponsesTest do
  use QuickTrain.DataCase, async: false
  alias QuickTrain.{Accounts, ProjectsFixture}
  alias QuickTrain.Tasks.Attempts.Attempt
  alias QuickTrain.Tasks.Progress.TaskQuestionProgress
  alias QuickTrain.Tasks.Responses.{QuestionResponse, Response}

  setup do
    context = ProjectsFixture.context!()
    source = ProjectsFixture.source!(context)

    project =
      ProjectsFixture.active!(context, source, audience: :external_users, external_access: :open)

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

  test "draft revisions serialize writes and one immutable submission reserves accepted capacity",
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
    progress = Ash.read_one!(TaskQuestionProgress, authorize?: false)
    assert {progress.accepted, progress.pending, progress.live} == {1, 0, 0}

    assert_raise Ash.Error.Invalid, fn ->
      save!(ctx, 1, %{outcome: :answered, family: :integer, integer_value: 1})
    end

    outcome = Ash.read_one!(QuestionResponse, authorize?: false)

    assert_raise Ash.Error.Invalid, ~r/response_submitted/, fn ->
      Ash.destroy!(outcome, action: :destroy_internal, authorize?: false)
    end
  end

  test "an allowed all-skipped submission contributes no target and preserves explicit reason",
       ctx do
    save!(ctx, 0, %{outcome: :answered, family: :integer, integer_value: 4})
    save!(ctx, 1, %{outcome: :skipped, family: :integer, reason: "Cannot assess"})
    submit!(ctx)
    outcome = Ash.read_one!(QuestionResponse, authorize?: false)
    assert outcome.outcome == :skipped
    assert is_nil(outcome.integer_value)
    assert outcome.skipped_at
    progress = Ash.read_one!(TaskQuestionProgress, authorize?: false)
    assert {progress.accepted, progress.skipped, progress.live, progress.failures} == {0, 1, 0, 1}
  end

  test "incomplete draft stays editable after a rejected submission", ctx do
    response = save!(ctx, 0, %{outcome: :answered, family: :integer})
    assert_raise Ash.Error.Invalid, fn -> submit!(ctx) end
    assert Ash.get!(Response, response.id, authorize?: false).state == :draft
    save!(ctx, 1, %{outcome: :answered, family: :integer, integer_value: 3})
    assert submit!(ctx).state == :submitted
  end

  test "revision increments use stored values even when the supplied response is stale" do
    response = Ash.read_one!(Response, authorize?: false)
    assert QuickTrain.Tasks.revise_response!(response, authorize?: false).revision == 1
    assert QuickTrain.Tasks.revise_response!(response, authorize?: false).revision == 2

    result =
      Ash.bulk_update!([response], :revise, %{},
        strategy: [:stream],
        authorize?: false,
        transaction: :all,
        return_records?: true
      )

    assert [%{revision: 3}] = result.records
  end

  defp save!(ctx, revision, answer) do
    action!(
      Response,
      :save_question,
      Map.merge(scope(ctx), %{
        question_id: ctx.source.form.question.id,
        expected_revision: revision,
        answer: answer
      }),
      ctx.worker
    )
  end

  defp submit!(ctx), do: action!(Response, :submit, scope(ctx), ctx.worker)

  defp scope(ctx),
    do: %{
      organization_id: ctx.context.org.id,
      project_id: ctx.project.id,
      attempt_id: ctx.attempt.id
    }

  defp action!(resource, action, args, actor),
    do: resource |> Ash.ActionInput.for_action(action, args, actor: actor) |> Ash.run_action!()
end
