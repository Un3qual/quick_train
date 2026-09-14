defmodule QuickTrain.Tasks.TaskReviewTest do
  use QuickTrain.DataCase, async: false

  alias QuickTrain.{Accounts, ProjectsFixture}
  alias QuickTrain.Tasks.{Attempt, AttemptQuestion, Progress, QuestionResponse, QuestionReview}
  alias QuickTrain.Tasks.{Response, ReviewDecision, Task, TaskQuestionProgress}
  alias QuickTrain.Tasks.{TaskInput, TaskItemCoverage}
  alias QuickTrain.Tasks.Workers.{ReconcileCoverage, ReconcileProgress}

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
      create!(Task, Map.merge(scope, %{canonical_key: <<1>>, canonical_membership: <<1>>}))

    progress =
      create!(
        TaskQuestionProgress,
        Map.merge(scope, %{
          task_id: task.id,
          question_id: source.form.question.id,
          target: 2,
          failure_threshold: 3
        })
      )

    Map.merge(context, %{
      project: project,
      task: task,
      progress: progress,
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
             skipped: 0,
             live: 0,
             failures: 0
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
             skipped: 0,
             live: 0,
             failures: 1
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

  test "skip and self review denial preserves all batch evidence and failure counts", ctx do
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
    assert counts(ctx).failures == 1
    assert counts(ctx).pending == 2
  end

  test "the same retry key has an independent scope for each question response", ctx do
    first = outcome!(ctx)
    second = outcome!(ctx)
    key = Ash.UUID.generate()
    first_request = %{request(first, :accept) | request_key: key}
    second_request = %{request(second, :accept) | request_key: key}
    assert {:ok, [first_decision, second_decision]} = batch(ctx, [first_request, second_request])
    assert first_decision.id != second_decision.id
    assert counts(ctx).accepted == 2
    assert {:ok, first_retry} = decide(ctx, first_request)
    assert {:ok, second_retry} = decide(ctx, second_request)
    assert first_retry.id != second_retry.id
    assert Ash.count!(ReviewDecision, authorize?: false) == 2
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

  test "manual submissions reserve capacity until a review makes that work available", ctx do
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
          worker_action!(Response, :save_question, ctx, worker, %{
            attempt_id: attempt.id,
            question_id: ctx.source.form.question.id,
            expected_revision: 0,
            answer: %{outcome: :answered, family: :integer, integer_value: 4}
          })

        assert worker_action!(Response, :submit, ctx, worker, %{attempt_id: attempt.id}).state ==
                 :submitted

        progress =
          TaskQuestionProgress
          |> Ash.Query.filter(task_id == ^attempt.task_id)
          |> Ash.read_one!(authorize?: false)

        assert {progress.accepted, progress.pending, progress.live} == {0, 1, 0}

        QuestionResponse
        |> Ash.Query.filter(response_id == ^response.id)
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

    assert resumed.status == :issued
    assert resumed.attempt.task_id == rejected.task_id
    assert Ash.count!(ReviewDecision, authorize?: false) == 2
  end

  test "automatic acceptance belongs only to answered outcomes and does not change projections",
       ctx do
    answered = outcome!(ctx, project_counts: false)
    skipped = outcome!(ctx, outcome: :skipped, project_counts: false)
    automatic = %{ctx.project | review_mode: :automatic}
    assert QuestionReview.initial_decision!(ctx.project, ctx.task, answered) == :pending
    assert QuestionReview.initial_decision!(automatic, ctx.task, skipped) == :skipped
    assert Ash.count!(ReviewDecision, authorize?: false) == 0
    assert QuestionReview.initial_decision!(automatic, ctx.task, answered) == :accepted
    [decision] = Ash.read!(ReviewDecision, authorize?: false, page: false)
    assert decision.origin == :system
    assert decision.request_key == nil
    assert decision.requester_id == nil
    assert decision.question_response_id == answered.id
    assert counts(ctx).accepted == 0
  end

  test "corrections clear attention before satisfaction and rebuilding agrees with evidence",
       ctx do
    Ash.Seed.update!(ctx.progress, %{target: 7, failure_threshold: 5})

    decisions =
      for _ <- 1..5 do
        outcome = outcome!(ctx)
        assert {:ok, decision} = decide(ctx, request(outcome, :reject, nil, "Rejected"))
        {outcome, decision}
      end

    assert current_progress(ctx).attention
    assert Ash.get!(Task, ctx.task.id, authorize?: false).state == :needs_attention
    [{outcome, decision} | _] = decisions
    assert {:ok, _} = decide(ctx, request(outcome, :accept, decision.id, "Corrected"))
    refute current_progress(ctx).attention
    assert counts(ctx).failures == 4
    assert Ash.get!(Task, ctx.task.id, authorize?: false).state == :open
    expected = counts(ctx)
    Ash.Seed.update!(current_progress(ctx), %{accepted: 0, failures: 99, attention: true})
    assert {:ok, _} = Progress.reconcile!(ctx.org.id, ctx.project.id, ctx.task.id)
    assert counts(ctx) == expected
    refute current_progress(ctx).attention
  end

  test "closed-project corrections move satisfied and cancelled projections without reviving attempts",
       ctx do
    Ash.Seed.update!(ctx.progress, %{target: 1})
    outcome = outcome!(ctx)
    assert {:ok, first} = decide(ctx, request(outcome, :accept))
    assert Ash.get!(Task, ctx.task.id, authorize?: false).state == :satisfied
    Ash.Seed.update!(ctx.project, %{state: :completed})
    assert {:ok, second} = decide(ctx, request(outcome, :reject, first.id, "Corrected"))
    assert Ash.get!(Task, ctx.task.id, authorize?: false).state == :cancelled
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

  test "accepted evidence can grow beyond the signed 32-bit boundary without clamping", ctx do
    outcome = outcome!(ctx)
    assert {:ok, rejected} = decide(ctx, request(outcome, :reject, nil, "Rejected"))
    Ash.Seed.update!(current_progress(ctx), %{target: 2_147_483_647, accepted: 2_147_483_647})
    assert {:ok, _} = decide(ctx, request(outcome, :accept, rejected.id, "Corrected"))
    assert counts(ctx).accepted == 2_147_483_648
    assert Ash.get!(Task, ctx.task.id, authorize?: false).state == :satisfied
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

  test "rebuilding counts terminal failures once and excludes unsubmitted draft payloads", ctx do
    accepted = outcome!(ctx)
    assert {:ok, _} = decide(ctx, request(accepted, :accept))
    rejected = outcome!(ctx)
    assert {:ok, _} = decide(ctx, request(rejected, :reject, nil, "Rejected"))
    outcome!(ctx)
    outcome!(ctx, outcome: :skipped)

    for state <- [:expired, :released, :cancelled, :in_progress] do
      draft = outcome!(ctx, project_counts: false)
      response = Ash.get!(Response, draft.response_id, authorize?: false)
      Ash.Seed.update!(response, %{state: :draft, submitted_at: nil})
      attempt = Ash.get!(Attempt, response.attempt_id, authorize?: false)
      Ash.Seed.update!(attempt, %{state: state})
      assert {:error, _} = decide(ctx, request(draft, :accept))
    end

    Ash.Seed.update!(current_progress(ctx), %{accepted: 99, live: 99, failures: 99})

    job = %Oban.Job{
      args: %{
        "organization_id" => ctx.org.id,
        "project_id" => ctx.project.id,
        "task_id" => ctx.task.id
      }
    }

    assert :ok = ReconcileProgress.perform(job)

    assert counts(ctx) == %{
             accepted: 1,
             pending: 1,
             rejected: 1,
             skipped: 1,
             live: 1,
             failures: 4
           }

    assert current_progress(ctx).attention
    assert :ok = ReconcileProgress.perform(job)
    assert counts(ctx).failures == 4
    assert Ash.count!(ReviewDecision, authorize?: false) == 2
  end

  test "coverage rebuilding counts each issued task input once despite repeated attempts", ctx do
    [item, other] = ProjectsFixture.items(ctx.project)

    create!(
      TaskInput,
      Map.merge(ctx.scope, %{
        task_id: ctx.task.id,
        project_item_id: item.id,
        revision_id: item.revision_id,
        input_slot_id: ctx.source.form.slot.id
      })
    )

    outcome!(ctx)
    outcome!(ctx)
    job = %Oban.Job{args: %{"organization_id" => ctx.org.id, "project_id" => ctx.project.id}}
    assert :ok = ReconcileCoverage.perform(job)
    coverage = Ash.read!(TaskItemCoverage, authorize?: false, page: false)

    assert Map.new(coverage, &{&1.project_item_id, &1.exposures}) == %{
             item.id => 1,
             other.id => 0
           }

    Enum.each(coverage, &Ash.Seed.update!(&1, %{exposures: 99}))
    assert :ok = ReconcileCoverage.perform(job)

    assert Map.new(
             Ash.read!(TaskItemCoverage, authorize?: false, page: false),
             &{&1.project_item_id, &1.exposures}
           ) == %{item.id => 1, other.id => 0}
  end

  @tag :committed_db
  test "concurrent reviewers serialize one successor and reconcile with committed decisions",
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

    results =
      concurrently([
        fn -> Progress.reconcile!(ctx.org.id, ctx.project.id, ctx.task.id) end,
        fn -> decide(ctx, correction) end
      ])

    assert Enum.all?(results, &match?({:ok, _}, &1))

    assert counts(ctx) == %{
             accepted: 1,
             pending: 0,
             rejected: 0,
             skipped: 0,
             live: 0,
             failures: 0
           }

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

    create!(
      AttemptQuestion,
      Map.merge(ctx.scope, %{
        task_id: ctx.task.id,
        attempt_id: attempt.id,
        question_id: ctx.progress.question_id
      })
    )

    response =
      create!(
        Response,
        Map.merge(ctx.scope, %{
          task_id: ctx.task.id,
          attempt_id: attempt.id,
          state: :draft
        })
      )

    outcome = Keyword.get(opts, :outcome, :answered)

    result =
      create!(
        QuestionResponse,
        Map.merge(ctx.scope, %{
          task_id: ctx.task.id,
          response_id: response.id,
          question_id: ctx.progress.question_id,
          outcome: outcome,
          family: :integer,
          integer_value: if(outcome == :answered, do: 3),
          reason: if(outcome == :skipped, do: "Unable to answer"),
          skipped_at: if(outcome == :skipped, do: DateTime.utc_now())
        })
      )

    Ash.update!(response, %{state: :submitted, submitted_at: DateTime.utc_now()},
      action: :update_internal,
      authorize?: false
    )

    Ash.update!(attempt, %{state: :submitted, terminal_at: DateTime.utc_now()},
      action: :update_internal,
      authorize?: false
    )

    if Keyword.get(opts, :project_counts, true) do
      delta = if outcome == :answered, do: %{pending: 1}, else: %{skipped: 1, failures: 1}

      Progress.change!(ctx.project, Ash.get!(Task, ctx.task.id, authorize?: false), %{
        ctx.progress.question_id => delta
      })
    end

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

  defp current_progress(ctx),
    do: Ash.get!(TaskQuestionProgress, ctx.progress.id, authorize?: false)

  defp counts(ctx),
    do:
      Map.take(current_progress(ctx), [:accepted, :pending, :rejected, :skipped, :live, :failures])

  defp create!(resource, attrs),
    do: Ash.create!(resource, attrs, action: :create_internal, authorize?: false)
end
