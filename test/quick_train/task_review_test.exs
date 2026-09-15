defmodule QuickTrain.Tasks.TaskReviewTest do
  use QuickTrain.DataCase, async: false

  alias QuickTrain.{Accounts, ProjectsFixture}
  alias QuickTrain.Tasks.Attempts.Attempt
  alias QuickTrain.Tasks.Responses.QuestionResponse
  alias QuickTrain.Tasks.Reviews.{QuestionReview, ReviewDecision}
  alias QuickTrain.Tasks.Task

  require Ash.Query

  setup do
    context =
      ProjectsFixture.context!(
        ~w(projects.read projects.manage forms.read forms.manage datasets.read datasets.manage tasks.review)
      )

    source = ProjectsFixture.source!(context)
    project = ProjectsFixture.active!(context, source, review_mode: :manual)

    scope = %{
      organization_id: project.organization_id,
      project_id: project.id,
      form_version_id: project.form_version_id
    }

    task =
      create!(
        Task,
        Map.merge(scope, %{
          explicit_group_id:
            hd(Ash.read!(QuickTrain.Projects.ExplicitGroup, authorize?: false)).id
        })
      )

    Map.merge(context, %{
      project: project,
      task: task,
      scope: scope,
      source: source
    })
  end

  test "manual decisions and corrections append history while identical requests converge", ctx do
    outcome = outcome!(ctx)
    request = Map.drop(request(outcome, :accept), [:reason, :expected_predecessor_id])
    assert {:ok, first} = decide(ctx, request)
    assert first.number == 1
    assert first.origin == :human
    assert first.requester_id == ctx.actor.id
    assert first.predecessor_id == nil

    assert counts(ctx) == %{
             accepted: 1,
             pending: 0,
             rejected: 0,
             skipped: 0
           }

    assert {:ok, retry} = decide(ctx, request)
    assert retry.id == first.id
    assert {:error, _} = decide(ctx, Map.put(request, :reason, "Changed retry"))

    correction = request(outcome, :reject, first.id, "Incorrect answer")
    assert {:ok, second} = decide(ctx, correction)
    assert second.number == 2
    assert second.predecessor_id == first.id

    assert counts(ctx) == %{
             accepted: 0,
             pending: 0,
             rejected: 1,
             skipped: 0
           }

    assert {:error, _} = decide(ctx, request(outcome, :accept, first.id, "Stale"))
    assert Ash.count!(ReviewDecision, authorize?: false) == 2
    assert Ash.get!(QuestionResponse, outcome.id, authorize?: false).integer_value == 3
  end

  test "request UUIDs are validated before single or batch writes", ctx do
    first = outcome!(ctx)
    second = outcome!(ctx)

    for key <- [nil, "", "invalid"] do
      assert {:error, _} = decide(ctx, %{request(first, :accept) | request_key: key})

      assert {:error, _} =
               batch(ctx, [
                 request(first, :accept),
                 %{request(second, :accept) | request_key: key}
               ])
    end

    assert Ash.count!(ReviewDecision, authorize?: false) == 0
    assert counts(ctx).pending == 2
  end

  test "review creation validates human and system provenance before batch persistence", ctx do
    outcome = outcome!(ctx)

    attrs =
      Map.merge(ctx.scope, %{
        task_id: ctx.task.id,
        question_id: outcome.question_id,
        question_response_id: outcome.id,
        number: 1,
        verdict: :accept
      })

    for provenance <- [
          %{origin: :human, requester_id: ctx.actor.id},
          %{origin: :human, request_key: Ash.UUID.generate()},
          %{origin: :system, verdict: :reject},
          %{origin: :system, requester_id: ctx.actor.id},
          %{origin: :system, request_key: Ash.UUID.generate()}
        ] do
      result =
        Ash.bulk_create([Map.merge(attrs, provenance)], ReviewDecision, :create_internal,
          authorize?: false,
          return_errors?: true
        )

      assert result.status == :error
    end

    refute Ash.exists?(ReviewDecision, authorize?: false)
  end

  test "skip and self review denial preserves all batch evidence", ctx do
    answered = outcome!(ctx)
    skipped = outcome!(ctx, outcome: :skipped)
    own = outcome!(ctx, worker: ctx.actor)
    assert {:error, _} = decide(ctx, request(own, :accept))

    for verdict <- [:accept, :reject] do
      assert {:error, _} = decide(ctx, request(skipped, verdict, nil, "Reason"))
      assert {:error, _} = batch(ctx, [request(answered, :accept), request(skipped, verdict)])
    end

    assert Ash.count!(ReviewDecision, authorize?: false) == 0
    assert counts(ctx).skipped == 1
    assert counts(ctx).pending == 2
  end

  test "the same retry key has an independent scope for each question response", ctx do
    first = outcome!(ctx)
    second = outcome!(ctx)
    key = Ash.UUID.generate()
    first_request = %{request(first, :accept) | request_key: key}
    second_request = %{request(second, :accept) | request_key: key}
    assert {:ok, [first_decision, second_decision]} = batch(ctx, [first_request, second_request])
    assert first_decision.question_response_id == first.id
    assert second_decision.question_response_id == second.id

    assert first_decision.id != second_decision.id
    assert counts(ctx).accepted == 2
    assert {:ok, first_retry} = decide(ctx, first_request)
    assert {:ok, second_retry} = decide(ctx, second_request)
    assert first_retry.id != second_retry.id
    assert Ash.count!(ReviewDecision, authorize?: false) == 2

    correction = request(first, :reject, first_decision.id, "Corrected")
    assert {:ok, [second_retry, corrected]} = batch(ctx, [second_request, correction])
    assert second_retry.id == second_decision.id
    assert corrected.question_response_id == first.id
    assert corrected.predecessor_id == first_decision.id
    assert corrected.number == 2
    assert counts(ctx).accepted == 1
    assert counts(ctx).rejected == 1
    assert Ash.count!(ReviewDecision, authorize?: false) == 3
  end

  test "inactive organizations deny new decisions, retries, corrections, and batches", ctx do
    outcome = outcome!(ctx)
    original = request(outcome, :accept)
    assert {:ok, first} = decide(ctx, original)
    Ash.Seed.update!(ctx.org, %{status: "inactive"})

    assert {:error, _} = decide(ctx, original)
    assert {:error, _} = decide(ctx, request(outcome, :reject, first.id, "Correction"))
    assert {:error, _} = batch(ctx, [request(outcome, :reject, first.id, "Correction")])
    assert Ash.count!(ReviewDecision, authorize?: false) == 1
    assert counts(ctx).accepted == 1
  end

  test "revoked accounts and memberships cannot replay or correct an earlier review", ctx do
    outcome = outcome!(ctx)
    original = request(outcome, :accept)
    assert {:ok, first} = decide(ctx, original)

    for record <- [ctx.actor, ctx.membership] do
      Ash.Seed.update!(record, %{status: "inactive"})
      assert {:error, _} = decide(ctx, original)
      assert {:error, _} = decide(ctx, request(outcome, :reject, first.id, "Correction"))
      assert {:error, _} = batch(ctx, [request(outcome, :reject, first.id, "Correction")])
      assert Ash.count!(ReviewDecision, authorize?: false) == 1
      assert counts(ctx).accepted == 1
      Ash.Seed.update!(record, %{status: "active"})
    end
  end

  test "review verdicts never reopen a submitted task", ctx do
    project =
      ProjectsFixture.active!(ctx, ctx.source,
        review_mode: :manual,
        audience: :external_users,
        external_access: :open
      )

    ctx = %{ctx | project: project}

    [first_worker, second_worker, next_worker] =
      for number <- 1..3,
          do: Accounts.register_user!("manual-#{number}@example.test", "Worker")

    outcomes =
      for worker <- [first_worker, second_worker] do
        allocation =
          worker_action!(Attempt, :fetch, ctx, worker, %{request_key: Ash.UUID.generate()})

        assert allocation.status == :issued
        attempt = allocation.attempt

        response =
          worker_action!(Attempt, :save_question, ctx, worker, %{
            attempt_id: attempt.id,
            question_id: ctx.source.form.question.id,
            expected_revision: 0,
            answer: %{outcome: :answered, family: :integer, integer_value: 4}
          })

        assert QuickTrain.Tasks.submit_response!(attempt, actor: worker).state ==
                 :submitted

        QuestionResponse
        |> Ash.Query.filter(attempt_id == ^response.id)
        |> Ash.read_one!(authorize?: false)
      end

    assert Ash.count!(ReviewDecision, authorize?: false) == 0

    waiting =
      worker_action!(Attempt, :fetch, ctx, next_worker, %{request_key: Ash.UUID.generate()})

    refute waiting.status == :issued
    [accepted, rejected] = outcomes
    assert {:ok, _} = decide(ctx, request(accepted, :accept))
    assert {:ok, _} = decide(ctx, request(rejected, :reject, nil, "Needs another answer"))

    resumed =
      worker_action!(Attempt, :fetch, ctx, next_worker, %{request_key: Ash.UUID.generate()})

    assert resumed.status == :no_work_for_worker
    assert Ash.count!(ReviewDecision, authorize?: false) == 2
  end

  test "automatic acceptance belongs only to answered outcomes",
       ctx do
    answered = outcome!(ctx)
    skipped = outcome!(ctx, outcome: :skipped)
    automatic = %{ctx.project | review_mode: :automatic}

    assert QuestionReview.initial_decisions!(ctx.project, [answered, skipped]) ==
             %{answered.id => :pending, skipped.id => :skipped}

    assert Ash.count!(ReviewDecision, authorize?: false) == 0

    assert QuestionReview.initial_decisions!(automatic, [answered, skipped]) ==
             %{answered.id => :accepted, skipped.id => :skipped}

    [decision] = Ash.read!(ReviewDecision, authorize?: false, page: false)
    assert decision.origin == :system
    assert decision.request_key == nil
    assert decision.requester_id == nil
    assert decision.question_response_id == answered.id
    assert counts(ctx).accepted == 1
  end

  test "closed-project corrections preserve satisfaction and terminal attempts",
       ctx do
    outcome = outcome!(ctx)
    assert {:ok, first} = decide(ctx, request(outcome, :accept))
    assert Ash.get!(Task, ctx.task.id, authorize?: false).state == :satisfied
    Ash.Seed.update!(ctx.project, %{state: :completed})
    assert {:ok, second} = decide(ctx, request(outcome, :reject, first.id, "Corrected"))
    assert Ash.get!(Task, ctx.task.id, authorize?: false).state == :satisfied
    assert {:ok, third} = decide(ctx, request(outcome, :accept, second.id, "Restored"))
    current = Ash.load!(outcome, [:effective_decision, :effective_verdict], authorize?: false)
    assert current.effective_decision.id == third.id
    assert current.effective_verdict == :accept
    assert Ash.get!(Task, ctx.task.id, authorize?: false).state == :satisfied

    assert Enum.all?(
             Ash.read!(Attempt, authorize?: false, page: false),
             &(&1.state == :submitted)
           )
  end

  test "rejection and correction reasons are nonblank without a task-specific length ceiling",
       ctx do
    outcome = outcome!(ctx)

    for reason <- [nil, "", " \n "] do
      assert {:error, _} = decide(ctx, request(outcome, :reject, nil, reason))
    end

    assert Ash.count!(ReviewDecision, authorize?: false) == 0
    assert {:ok, accepted} = decide(ctx, request(outcome, :accept))
    assert {:error, _} = decide(ctx, request(outcome, :accept, accepted.id))
    long_reason = String.duplicate("Correction reason ", 1000)
    assert {:ok, correction} = decide(ctx, request(outcome, :reject, accepted.id, long_reason))
    assert correction.reason == long_reason
  end

  @tag :committed_db
  test "concurrent reviewers serialize successors and idempotent corrections",
       ctx do
    outcome = outcome!(ctx)
    first = request(outcome, :accept)
    second = request(outcome, :reject, nil, "Rejected")
    results = concurrently([fn -> decide(ctx, first) end, fn -> decide(ctx, second) end])
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, _}, &1)) == 1
    assert Ash.count!(ReviewDecision, authorize?: false) == 1

    current = Ash.load!(outcome, :effective_decision, authorize?: false).effective_decision
    correction = request(outcome, :accept, current.id, "Reconciled correction")

    results = concurrently([fn -> decide(ctx, correction) end, fn -> decide(ctx, correction) end])
    assert [{:ok, first_retry}, {:ok, second_retry}] = results
    assert first_retry.id == second_retry.id
    assert counts(ctx).accepted == 1

    assert Ash.count!(ReviewDecision, authorize?: false) == 2
  end

  defp outcome!(ctx, opts \\ []) do
    number = System.unique_integer([:positive])
    worker = opts[:worker] || Accounts.register_user!("worker-#{number}@example.test", "Worker")

    attempt =
      create!(
        Attempt,
        Map.merge(ctx.scope, %{
          task_id: ctx.task.id,
          worker_id: worker.id,
          requester_id: worker.id,
          request_key: Ash.UUID.generate(),
          operation: :fetch,
          state: :in_progress,
          deadline: DateTime.add(DateTime.utc_now(), 600, :second)
        })
      )

    outcome = Keyword.get(opts, :outcome, :answered)

    result =
      create!(
        QuestionResponse,
        Map.merge(ctx.scope, %{
          task_id: ctx.task.id,
          attempt_id: attempt.id,
          question_id: ctx.source.form.question.id,
          outcome: outcome,
          family: :integer,
          integer_value: if(outcome == :answered, do: 3),
          reason: if(outcome == :skipped, do: "Unable to answer"),
          skipped_at: if(outcome == :skipped, do: DateTime.utc_now())
        })
      )

    Ash.update!(attempt, %{state: :submitted, terminal_at: DateTime.utc_now()},
      action: :update_internal,
      authorize?: false
    )

    result
  end

  defp request(outcome, verdict, predecessor \\ nil, reason \\ nil),
    do: %{
      question_response_id: outcome.id,
      request_key: Ash.UUID.generate(),
      verdict: verdict,
      expected_predecessor_id: predecessor,
      reason: reason
    }

  defp decide(ctx, attrs), do: run(ctx, :decide, attrs)
  defp batch(ctx, decisions), do: run(ctx, :review_batch, %{decisions: decisions})

  defp worker_action!(resource, action, ctx, worker, args) do
    resource
    |> Ash.ActionInput.for_action(
      action,
      Map.merge(args, %{organization_id: ctx.org.id, project_id: ctx.project.id}),
      actor: worker
    )
    |> Ash.run_action!()
  end

  defp run(ctx, action, attrs) do
    ReviewDecision
    |> Ash.ActionInput.for_action(
      action,
      Map.merge(attrs, %{organization_id: ctx.org.id, project_id: ctx.project.id}),
      actor: ctx.actor
    )
    |> Ash.run_action()
  end

  defp counts(ctx) do
    QuestionResponse
    |> Ash.Query.filter(task_id == ^ctx.task.id)
    |> Ash.Query.load(:effective_decision)
    |> Ash.read!(authorize?: false, page: false)
    |> Enum.frequencies_by(&QuestionReview.effective_status/1)
    |> then(&Map.merge(%{accepted: 0, pending: 0, rejected: 0, skipped: 0}, &1))
  end

  defp create!(resource, attrs),
    do: Ash.create!(resource, attrs, action: :create_internal, authorize?: false)
end
