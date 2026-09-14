defmodule QuickTrain.Tasks.TaskReadsTest do
  use QuickTrain.DataCase, async: false
  alias QuickTrain.{Accounts, Authorization, Forms, Organizations, ProjectsFixture}
  alias QuickTrain.Datasets.DatasetValue
  alias QuickTrain.Forms.FormVersion
  alias QuickTrain.Projects.Management
  alias QuickTrain.Tasks.{Access, TaskInput}
  alias QuickTrain.Tasks.Attempts.Attempt
  alias QuickTrain.Tasks.Responses.QuestionResponse
  require Ash.Query

  setup tags do
    context =
      ProjectsFixture.context!(
        ~w(projects.read projects.manage forms.read forms.manage datasets.read datasets.manage assets.manage)
      )

    source =
      if tags[:rich_source], do: rich_source!(context), else: ProjectsFixture.source!(context)

    project =
      ProjectsFixture.configured!(context, source,
        audience: :external_users,
        external_access: :open,
        lease_minutes: 1
      )

    if tags[:rich_source] do
      for {requirement, field} <- source.extra_bindings do
        QuickTrain.Projects.set_binding!(
          context.org.id,
          project.id,
          %{
            requirement_id: requirement.id,
            field_definition_id: field.id
          },
          actor: context.actor
        )
      end
    end

    project =
      QuickTrain.Projects.activate_project!(context.org.id, project.id, actor: context.actor)

    worker = Accounts.register_user!("reader-worker@example.test", "Worker")

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

  test "live worker reads pinned definitions, offered policies, and only exact bound values",
       ctx do
    bundle = action!(Attempt, :work_bundle, scope(ctx), ctx.worker)

    bundle =
      Ash.load!(
        bundle,
        [
          form_version: [questions: :integer_constraints],
          offered_questions: [:skip_allowed, :reason_required],
          input_presentations: [task_input: :requirements]
        ],
        actor: ctx.worker
      )

    assert bundle.form_version.id == ctx.source.form.version.id
    assert hd(bundle.form_version.questions).integer_constraints.minimum == 1
    assert hd(bundle.offered_questions).skip_allowed
    assert hd(bundle.offered_questions).reason_required
    input = hd(bundle.input_presentations).task_input
    assert input.revision_id in Enum.map(ctx.source.revisions, & &1.id)

    bound =
      action!(
        TaskInput,
        :bound_value,
        Map.merge(scope(ctx), %{task_input_id: input.id, requirement_id: ctx.source.form.field.id}),
        ctx.worker
      )

    refute bound.missing
    value = Ash.load!(bound.value, [:text_value, :field_definition], actor: ctx.worker)
    assert value.text_value.value =~ "Body"
    assert value.field_definition.id == ctx.source.field.id

    assert {:error, _} =
             Forms.get_form_version(ctx.context.org.id, ctx.source.form.version.id,
               actor: ctx.worker
             )

    assert {:error, _} = Ash.read(DatasetValue, actor: ctx.worker)
    assert {:error, _} = Ash.read(DatasetValue, actor: ctx.worker, context: %{task_access: true})
  end

  test "malformed definition scopes return normal Ash validation errors", ctx do
    args = Map.put(scope(ctx), :id, ctx.source.form.version.id)

    for inputs <- [%{}, Map.delete(args, :project_id), Map.put(args, :organization_id, "invalid")] do
      query = Ash.Query.for_read(FormVersion, :get_task_definition, inputs, actor: ctx.worker)
      refute query.valid?
      assert {:error, %Ash.Error.Invalid{}} = Ash.read_one(query)
    end
  end

  test "substitution and revocation cannot renew work access", ctx do
    stranger = Accounts.register_user!("stranger-read@example.test", "Stranger")
    assert {:error, _} = action(Attempt, :work_bundle, scope(ctx), stranger)
    other = ProjectsFixture.draft!(ctx.context, ctx.source)

    assert {:error, _} =
             action(Attempt, :work_bundle, %{scope(ctx) | project_id: other.id}, ctx.worker)

    QuickTrain.Projects.set_worker_access!(
      ctx.context.org.id,
      ctx.project.id,
      %{
        user_id: ctx.worker.id,
        disposition: :block
      },
      actor: ctx.context.actor
    )

    assert {:error, _} = action(Attempt, :work_bundle, scope(ctx), ctx.worker)

    assert {:error, _} =
             FormVersion
             |> Ash.Query.for_read(
               :get_task_definition,
               Map.merge(scope(ctx), %{id: ctx.source.form.version.id}),
               actor: ctx.worker
             )
             |> Ash.read_one()
  end

  test "result readers see submitted evidence and full typed contract without foundation grants",
       ctx do
    reader = result_reader!(ctx)
    save!(ctx)
    assert rows(QuestionResponse, :list_audit, ctx, reader) == []
    submitted = action!(Attempt, :submit, scope(ctx), ctx.worker)
    assert submitted.state == :submitted
    [outcome] = rows(QuestionResponse, :list_accepted, ctx, reader)

    outcome =
      Ash.load!(
        outcome,
        [question: :integer_constraints, review_decisions: [], effective_decision: []],
        actor: reader
      )

    assert outcome.integer_value == 4
    assert outcome.question.renderer == :stars
    assert outcome.question.integer_constraints.maximum == 5
    assert outcome.effective_decision.verdict == :accept
    assert [_] = outcome.review_decisions
    [attempt] = rows(Attempt, :list_audit, ctx, reader)

    attempt =
      Ash.load!(
        attempt,
        [form_version: [:elements, :requirements], input_presentations: :task_input],
        actor: reader
      )

    assert hd(attempt.form_version.elements).question_id == ctx.source.form.question.id
    input = hd(attempt.input_presentations).task_input

    bound =
      action!(
        TaskInput,
        :bound_value,
        %{
          organization_id: ctx.context.org.id,
          project_id: ctx.project.id,
          task_input_id: input.id,
          requirement_id: ctx.source.form.field.id
        },
        reader
      )

    assert bound.value.field_definition_id == ctx.source.field.id

    assert {:error, _} =
             Forms.get_form_version(ctx.context.org.id, ctx.source.form.version.id, actor: reader)

    assert {:error, _} = action(Attempt, :work_bundle, scope(ctx), reader)
  end

  test "terminal receipts expose status while terminal draft descendants stay unreadable", ctx do
    save!(ctx)
    released = action!(Attempt, :release, scope(ctx), ctx.worker)
    assert released.state == :released
    assert {:error, _} = action(Attempt, :work_bundle, scope(ctx), ctx.worker)
    receipt = action!(Attempt, :receipt, scope(ctx), ctx.worker)
    receipt = Ash.load!(receipt, [questions: :review_status], actor: ctx.worker)
    assert hd(receipt.questions).review_status == :unsubmitted
    reader = result_reader!(ctx)
    assert rows(QuestionResponse, :list_audit, ctx, reader) == []
    [attempt] = rows(Attempt, :list_audit, ctx, reader)
    attempt = Ash.load!(attempt, [:outcomes, :offered_questions], actor: reader)
    assert attempt.outcomes == []
    assert [_] = attempt.offered_questions
    assert {:error, _} = Ash.read(QuestionResponse, actor: ctx.worker)
  end

  test "expired physical attempts deny live bundles before cleanup", ctx do
    Repo.query!(
      "UPDATE attempts SET deadline = clock_timestamp() - interval '1 second' WHERE id = $1",
      [Ecto.UUID.dump!(ctx.attempt.id)]
    )

    assert {:error, error} = action(Attempt, :work_bundle, scope(ctx), ctx.worker)
    assert Exception.message(error) =~ "attempt_expired"
    assert Ash.get!(Attempt, ctx.attempt.id, authorize?: false).state == :claimed
  end

  test "known task definitions resolve through the scoped GraphQL boundary", ctx do
    document = """
    query($organization: ID!, $project: ID!, $attempt: ID, $version: ID!, $field: ID!) {
      taskFormVersion(organizationId: $organization, projectId: $project, attemptId: $attempt, id: $version) {
        id questions(first: 1) { edges { node { id renderer integerConstraints { minimum maximum } } } }
      }
      taskFieldDefinition(organizationId: $organization, projectId: $project, attemptId: $attempt, id: $field) { id key }
    }
    """

    vars = %{
      "organization" => ctx.context.org.id,
      "project" => ctx.project.id,
      "attempt" => ctx.attempt.id,
      "version" => ctx.source.form.version.id,
      "field" => ctx.source.field.id
    }

    assert {:ok, %{data: data} = result} =
             Absinthe.run(document, QuickTrainWeb.GraphQL.Schema,
               variables: vars,
               context: %{actor: ctx.worker}
             )

    refute Map.has_key?(result, :errors)
    assert data["taskFormVersion"]["id"] == ctx.source.form.version.id
    assert data["taskFieldDefinition"]["key"] == "body"
    reader = result_reader!(ctx)

    assert {:ok, %{data: data} = result} =
             Absinthe.run(document, QuickTrainWeb.GraphQL.Schema,
               variables: Map.delete(vars, "attempt"),
               context: %{actor: reader}
             )

    refute Map.has_key?(result, :errors)
    assert data["taskFormVersion"]["id"] == ctx.source.form.version.id
    other = QuickTrain.FormsFixture.draft!(ctx.context, "unrelated")

    assert {:ok, rejected} =
             Absinthe.run(document, QuickTrainWeb.GraphQL.Schema,
               variables: %{vars | "version" => other.version.id},
               context: %{actor: ctx.worker}
             )

    assert get_in(rejected, [:data, "taskFormVersion"]) == nil
  end

  test "explicit result traversal excludes the reader's own live drafts", ctx do
    reader = result_reader!(ctx, ctx.worker)
    save!(ctx)

    query =
      QuickTrain.Tasks.Task
      |> Ash.Query.for_read(:list_audit, Map.drop(scope(ctx), [:attempt_id]), actor: reader)
      |> Ash.Query.load([:outcomes, :attempts, :progress])

    [task] = Ash.read!(query).results
    assert task.outcomes == []
    assert task.attempts == []
    assert [_] = task.progress
    assert [_] = rows(QuickTrain.Tasks.Progress.TaskItemCoverage, :list_audit, ctx, reader)
    assert rows(QuickTrain.Tasks.Progress.TaskItemCoverage, :list_accepted, ctx, reader) == []

    bundle =
      action!(Attempt, :work_bundle, scope(ctx), reader)
      |> Ash.load!([:outcomes], actor: reader)

    assert [_] = bundle.outcomes

    action!(Attempt, :submit, scope(ctx), reader)
    [task] = Ash.read!(query).results
    assert [_] = task.outcomes
    assert [_] = task.attempts
    assert [_] = rows(QuickTrain.Tasks.Progress.TaskItemCoverage, :list_accepted, ctx, reader)

    accepted =
      QuickTrain.Tasks.Task
      |> Ash.Query.for_read(:list_accepted, Map.drop(scope(ctx), [:attempt_id]), actor: reader)
      |> Ash.Query.load(outcomes: :review_decisions)

    [task] = Ash.read!(accepted).results
    [outcome] = task.outcomes
    assert [_] = outcome.review_decisions
    [decision] = outcome.review_decisions

    Ash.create!(
      QuickTrain.Tasks.Reviews.ReviewDecision,
      %{
        organization_id: outcome.organization_id,
        project_id: outcome.project_id,
        form_version_id: outcome.form_version_id,
        task_id: outcome.task_id,
        question_id: outcome.question_id,
        question_response_id: outcome.id,
        origin: :human,
        verdict: :reject,
        number: 2,
        predecessor_id: decision.id,
        requester_id: reader.id,
        request_key: Ash.UUID.generate()
      },
      action: :create_internal,
      authorize?: false
    )

    assert Ash.read!(accepted).results == []
    [task] = Ash.read!(query).results
    assert [_] = task.outcomes
    assert rows(QuickTrain.Tasks.Reviews.ReviewDecision, :list_accepted, ctx, reader) == []
    assert [_, _] = rows(QuickTrain.Tasks.Reviews.ReviewDecision, :list_audit, ctx, reader)
  end

  @tag :rich_source
  test "source context preserves optional absence and prevents forged and reverse traversal",
       ctx do
    reader = result_reader!(ctx)
    bundle = action!(Attempt, :work_bundle, scope(ctx), ctx.worker)
    bundle = Ash.load!(bundle, [input_presentations: :task_input], actor: ctx.worker)
    input = hd(bundle.input_presentations).task_input
    args = Map.merge(scope(ctx), %{task_input_id: input.id, requirement_id: ctx.source.note.id})
    absent = action!(TaskInput, :bound_value, args, ctx.worker)
    assert absent.missing
    assert is_nil(absent.value)
    assert absent.field_definition_id == ctx.source.note_field.id
    assert absent.revision_id == input.revision_id

    bindings = rows(QuickTrain.Projects.ProjectInputBinding, :list_result_bindings, ctx, reader)
    assert [_, _, _] = bindings
    bindings = Ash.load!(bindings, [:requirement, :field_definition], actor: reader)

    assert Enum.any?(
             bindings,
             &(&1.requirement.key == "download" and &1.field_definition.key == "download")
           )

    assert {:error, _} =
             QuickTrain.Projects.ProjectInputBinding
             |> Ash.Query.for_read(:list_result_bindings, Map.drop(scope(ctx), [:attempt_id]),
               actor: ctx.worker
             )
             |> Ash.read()

    secret_values =
      DatasetValue
      |> Ash.Query.filter(field_definition_id == ^ctx.source.secret.id)
      |> Ash.read!(authorize?: false)

    secret_ids = Enum.map(secret_values, & &1.id)

    for actor <- [ctx.worker, reader] do
      assert_empty_read(DatasetValue, secret_ids, actor, %{
        source: QuickTrain.Datasets.DatasetRecord,
        name: :values
      })

      secret_children =
        Ash.load!(secret_values, :text_value, authorize?: false) |> Enum.map(& &1.text_value.id)

      assert_empty_read(DatasetValue.Text, secret_children, actor, %{
        source: DatasetValue,
        name: :text_value
      })

      assert_empty_read(
        QuickTrain.Datasets.DatasetFieldDefinition,
        [ctx.source.secret.id],
        actor,
        %{source: DatasetValue, name: :field_definition}
      )

      assert_empty_read(QuickTrain.Datasets.DatasetRecordType, [ctx.source.root.id], actor, %{
        source: QuickTrain.Datasets.DatasetFieldDefinition,
        name: :record_type
      })
    end

    unissued = Enum.find(ctx.source.revisions, &(&1.id != input.revision_id))

    [unissued_value] =
      DatasetValue
      |> Ash.Query.filter(
        record_id == ^unissued.root_record_id and field_definition_id == ^ctx.source.field.id
      )
      |> Ash.read!(authorize?: false)

    assert_empty_read(DatasetValue, [unissued_value.id], ctx.worker, %{
      source: QuickTrain.Datasets.DatasetRecord,
      name: :values
    })

    assert_empty_read(DatasetValue, [unissued_value.id], reader, %{
      source: QuickTrain.Datasets.DatasetRecord,
      name: :values
    })

    other =
      ProjectsFixture.configured!(ctx.context, ctx.source,
        audience: :external_users,
        external_access: :open
      )

    for {requirement, field} <- ctx.source.extra_bindings do
      QuickTrain.Projects.set_binding!(
        ctx.context.org.id,
        other.id,
        %{
          requirement_id: requirement.id,
          field_definition_id: field.id
        },
        actor: ctx.context.actor
      )
    end

    QuickTrain.Projects.set_binding!(
      ctx.context.org.id,
      other.id,
      %{
        requirement_id: ctx.source.form.field.id,
        field_definition_id: ctx.source.secret.id
      },
      actor: ctx.context.actor
    )

    other =
      QuickTrain.Projects.activate_project!(ctx.context.org.id, other.id,
        actor: ctx.context.actor
      )

    action!(
      Attempt,
      :fetch,
      %{
        organization_id: ctx.context.org.id,
        project_id: other.id,
        request_key: Ash.UUID.generate()
      },
      ctx.worker
    )

    query = """
    { taskFieldDefinition(organizationId: "#{ctx.context.org.id}", projectId: "#{ctx.project.id}",
       id: "#{ctx.source.secret.id}") { id key } }
    """

    assert {:ok, rejected} =
             Absinthe.run(query, QuickTrainWeb.GraphQL.Schema, context: %{actor: reader})

    assert get_in(rejected, [:data, "taskFieldDefinition"]) == nil

    body =
      action!(
        TaskInput,
        :bound_value,
        %{args | requirement_id: ctx.source.form.field.id},
        ctx.worker
      )

    assert Ash.load!(body.value, :text_value, actor: ctx.worker).text_value.value =~ "Body"

    QuickTrain.Projects.set_worker_access!(
      ctx.context.org.id,
      ctx.project.id,
      %{
        user_id: ctx.worker.id,
        disposition: :block
      },
      actor: ctx.context.actor
    )

    assert_empty_read(DatasetValue, [body.value.id], ctx.worker, %{
      source: QuickTrain.Datasets.DatasetRecord,
      name: :values
    })
  end

  @tag :rich_source
  test "bound source downloads preserve opaque storage and current task authority", ctx do
    alias QuickTrain.Assets.Storage.InMemory

    bundle =
      action!(Attempt, :work_bundle, scope(ctx), ctx.worker)
      |> Ash.load!([input_presentations: :task_input], actor: ctx.worker)

    input = hd(bundle.input_presentations).task_input

    args =
      Map.merge(scope(ctx), %{task_input_id: input.id, requirement_id: ctx.source.download.id})

    bound = action!(TaskInput, :bound_value, args, ctx.worker)
    assert bound.asset.id == ctx.source.asset.id
    assert bound.asset.sha256 == :crypto.hash(:sha256, "Source attachment")
    access = action!(TaskInput, :source_download, args, ctx.worker)
    assert access.read_access.cache_control == "no-store"
    assert access.read_access.referrer_policy == "no-referrer"
    assert DateTime.compare(access.read_access.expires_at, ctx.attempt.deadline) != :gt
    assert DateTime.diff(access.read_access.expires_at, DateTime.utc_now(), :second) <= 300
    assert {:ok, "Source attachment"} = InMemory.read_sealed(access.read_access)

    assert {:error, _} =
             QuickTrain.Assets.get_asset_access(ctx.source.asset.id, ctx.context.org.id,
               actor: ctx.worker
             )

    assert {:error, _} =
             action(
               TaskInput,
               :source_download,
               %{args | requirement_id: ctx.source.note.id},
               ctx.worker
             )

    action!(Attempt, :release, scope(ctx), ctx.worker)
    assert {:error, _} = action(TaskInput, :source_download, args, ctx.worker)
    reader = result_reader!(ctx)

    assert action!(TaskInput, :source_download, Map.delete(args, :attempt_id), reader).asset.id ==
             ctx.source.asset.id

    membership =
      QuickTrain.Organizations.Membership
      |> Ash.Query.filter(user_id == ^reader.id and organization_id == ^ctx.context.org.id)
      |> Ash.read_one!(authorize?: false)

    Organizations.deactivate_membership!(membership)

    assert {:error, _} =
             action(TaskInput, :source_download, Map.delete(args, :attempt_id), reader)
  end

  @tag :committed_db
  test "a blocked read rechecks wall-clock expiry after the project lock", ctx do
    parent = self()

    {:ok, task} =
      Repo.transaction(fn ->
        Management.lock!(ctx.context.org.id, ctx.project.id)

        task =
          Task.async(fn ->
            Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
              Repo.transaction(fn ->
                %{rows: [[backend]]} = Repo.query!("SELECT pg_backend_pid()")
                send(parent, {:reader_connection, backend})
                Access.project!(ctx.context.org.id, ctx.project.id)
                Ash.load!(ctx.attempt, :offered_questions, actor: ctx.worker).offered_questions
              end)
            end)
          end)

        assert_receive {:reader_connection, backend}, 5_000
        await_lock(backend, System.monotonic_time(:millisecond) + 5_000)

        Repo.query!(
          "UPDATE attempts SET deadline = clock_timestamp() + interval '50 milliseconds' WHERE id = $1",
          [Ecto.UUID.dump!(ctx.attempt.id)]
        )

        Repo.query!("SELECT pg_sleep(0.1)")
        task
      end)

    assert {:ok, []} = Task.await(task, 10_000)
    assert {:error, error} = action(Attempt, :work_bundle, scope(ctx), ctx.worker)
    assert Exception.message(error) =~ "attempt_expired"
  end

  defp await_lock(backend, deadline) do
    %{rows: [[waiting]]} =
      Repo.query!("SELECT wait_event_type = 'Lock' FROM pg_stat_activity WHERE pid = $1", [
        backend
      ])

    if waiting != true do
      assert System.monotonic_time(:millisecond) < deadline
      Process.sleep(10)
      await_lock(backend, deadline)
    end
  end

  defp assert_empty_read(resource, ids, actor, accessing_from) do
    query =
      resource
      |> Ash.Query.filter(id in ^ids)
      |> Ash.Query.set_context(%{accessing_from: accessing_from})

    case Ash.read(query, actor: actor, page: false) do
      {:ok, []} -> :ok
      {:error, %Ash.Error.Forbidden{}} -> :ok
      other -> flunk("Expected scoped denial, got #{inspect(other)}")
    end
  end

  defp rich_source!(context) do
    alias QuickTrain.{Assets, Datasets, FormsFixture}
    alias QuickTrain.Assets.Storage.InMemory
    alias QuickTrain.Forms.Inputs.InputFieldRequirement
    form = FormsFixture.rating!(context)

    note =
      FormsFixture.add!(InputFieldRequirement, context, form.version, %{
        input_slot_id: form.slot.id,
        key: "note",
        value_family: :text,
        required: false
      })

    download =
      FormsFixture.add!(InputFieldRequirement, context, form.version, %{
        input_slot_id: form.slot.id,
        key: "download",
        value_family: :asset,
        required: false,
        intended_use: :download
      })

    version =
      Forms.publish_form_version!(context.org.id, %{version_id: form.version.id},
        actor: context.actor
      )

    dataset = Datasets.create_dataset!(context.org.id, "rich", "Rich", actor: context.actor)
    schema = Datasets.create_schema_version!(context.org.id, dataset.id, actor: context.actor)

    root =
      Datasets.add_record_type!(context.org.id, schema.id, "item", "Item", actor: context.actor)

    [field, secret, note_field, download_field] =
      for {key, family, required} <- [
            {"body", "text", true},
            {"secret", "text", true},
            {"note", "text", false},
            {"download", "asset", false}
          ] do
        Datasets.add_field_definition!(
          context.org.id,
          root.id,
          key,
          key,
          family,
          "single",
          required,
          actor: context.actor
        )
      end

    schema =
      Datasets.publish_schema_version!(context.org.id, schema.id, root.id, actor: context.actor)

    InMemory.reset()
    bytes = "Source attachment"

    registration =
      Assets.register_asset!(
        context.org.id,
        Base.encode16(:crypto.hash(:sha256, bytes), case: :lower),
        byte_size(bytes),
        "text/plain",
        actor: context.actor
      )

    :ok = InMemory.put_staging(registration.upload_access, bytes)

    asset =
      Assets.finalize_asset!(registration.asset.id, context.org.id, actor: context.actor).asset

    revisions =
      for number <- 1..2 do
        Datasets.put_item_revision!(
          context.org.id,
          dataset.id,
          schema.id,
          nil,
          "rich-#{number}",
          [
            %{field: "body", text: "Body #{number}"},
            %{field: "secret", text: "Private #{number}"},
            %{field: "download", asset_id: asset.id}
          ],
          actor: context.actor
        ).revision
      end

    %{
      form: %{form | version: version},
      dataset: dataset,
      schema: schema,
      root: root,
      field: field,
      revisions: revisions,
      secret: secret,
      note: note,
      download: download,
      note_field: note_field,
      asset: asset,
      extra_bindings: [{note, note_field}, {download, download_field}]
    }
  end

  defp save!(ctx),
    do:
      action!(
        Attempt,
        :save_question,
        Map.merge(scope(ctx), %{
          question_id: ctx.source.form.question.id,
          expected_revision: 0,
          answer: %{outcome: :answered, family: :integer, integer_value: 4}
        }),
        ctx.worker
      )

  defp scope(ctx),
    do: %{
      organization_id: ctx.context.org.id,
      project_id: ctx.project.id,
      attempt_id: ctx.attempt.id
    }

  defp action(resource, action, args, actor),
    do: resource |> Ash.ActionInput.for_action(action, args, actor: actor) |> Ash.run_action()

  defp action!(resource, action, args, actor),
    do: resource |> Ash.ActionInput.for_action(action, args, actor: actor) |> Ash.run_action!()

  defp rows(resource, action, ctx, actor) do
    resource
    |> Ash.Query.for_read(
      action,
      %{organization_id: ctx.context.org.id, project_id: ctx.project.id},
      actor: actor
    )
    |> Ash.read!()
    |> Map.fetch!(:results)
  end

  defp result_reader!(ctx, actor \\ nil) do
    actor = actor || Accounts.register_user!("results@example.test", "Results")
    Organizations.add_member!(ctx.context.org.id, actor.id)
    role = Authorization.create_role!(ctx.context.org.id, "results", "Results")
    Authorization.assign_role!(ctx.context.org.id, actor.id, role.id)

    capability =
      Authorization.create_capability!("tasks.results.read", "Read results",
        upsert?: true,
        upsert_identity: :key,
        upsert_fields: []
      )

    Authorization.grant_capability!(role.id, capability.id)
    actor
  end
end
