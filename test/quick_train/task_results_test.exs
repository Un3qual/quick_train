defmodule QuickTrain.Tasks.ResultExportTest do
  use QuickTrain.DataCase, async: false
  @moduletag :committed_db
  alias QuickTrain.Accounts
  alias QuickTrain.Assets
  alias QuickTrain.Assets.Asset
  alias QuickTrain.Assets.Storage.InMemory
  alias QuickTrain.Authorization
  alias QuickTrain.Datasets
  alias QuickTrain.Datasets.DatasetItemRevision
  alias QuickTrain.Datasets.DatasetRecord.Values
  alias QuickTrain.Datasets.DatasetValue
  alias QuickTrain.Forms
  alias QuickTrain.Forms.Inputs.InputSlotDefinition
  alias QuickTrain.Forms.Labels.Label
  alias QuickTrain.Forms.Labels.LabelSet
  alias QuickTrain.Forms.Presentation.PresentationElement
  alias QuickTrain.Forms.Questions.Constraints.AnnotationConstraints
  alias QuickTrain.Forms.Questions.Constraints.DecimalConstraints
  alias QuickTrain.Forms.Questions.Constraints.SelectionConstraints
  alias QuickTrain.Forms.Questions.QuestionDefinition
  alias QuickTrain.Forms.Questions.QuestionOption
  alias QuickTrain.FormsFixture
  alias QuickTrain.Organizations
  alias QuickTrain.ProjectsFixture
  alias QuickTrain.Repo
  alias QuickTrain.Tasks
  alias QuickTrain.Tasks.Attempt
  alias QuickTrain.Tasks.Exports.Snapshot
  alias QuickTrain.Tasks.QuestionResponse
  alias QuickTrain.Tasks.Response
  alias QuickTrain.Tasks.ResultExport
  alias QuickTrain.Tasks.ResultExporting
  alias QuickTrain.Tasks.ReviewDecision
  alias QuickTrain.Tasks.TaskInput
  alias QuickTrain.Tasks.TextSpan

  require Ash.Query

  setup tags do
    context =
      ProjectsFixture.context!(
        ~w(projects.read projects.manage forms.read forms.manage datasets.read datasets.manage tasks.results.read assets.read assets.manage),
        "exports-#{System.unique_integer([:positive])}"
      )

    source = if tags[:rich], do: rich_source!(context), else: ProjectsFixture.source!(context)

    project =
      ProjectsFixture.draft!(context, source, audience: :external_users, external_access: :open)

    ProjectsFixture.run!(context, project, :enroll_revisions, %{
      revision_ids: Enum.map(source.revisions, & &1.id)
    })

    ProjectsFixture.run!(context, project, :set_binding, %{
      requirement_id: source.form.field.id,
      field_definition_id: source.field.id
    })

    ProjectsFixture.run!(context, project, :set_slot_policy, %{
      input_slot_id: source.form.slot.id,
      item_count: if(tags[:rich], do: 2, else: 1),
      shuffle: false
    })

    ProjectsFixture.run!(context, project, :set_question_policy, %{
      question_id: source.form.question.id,
      accepted_target: 1,
      skip_allowed: true,
      reason_required: true,
      failure_threshold: 3
    })

    for question <- Map.get(source, :extra_questions, []),
        do:
          ProjectsFixture.run!(context, project, :set_question_policy, %{
            question_id: question.id,
            accepted_target: 1,
            skip_allowed: true,
            reason_required: false,
            failure_threshold: 3
          })

    if tags[:rich],
      do:
        ProjectsFixture.run!(context, project, :set_slot_policy, %{
          input_slot_id: source.form.slot.id,
          item_count: 2,
          shuffle: false
        })

    project = ProjectsFixture.run!(context, project, :activate)
    :ok = InMemory.reset()
    %{context: context, project: project, source: source}
  end

  test "request UUIDs fail before persistence and identical requests share one job", scope do
    assert {:error, _} = request(scope, %{request_key: "invalid"})
    assert Ash.count!(ResultExport, authorize?: false) == 0

    key = Ash.UUID.generate()
    assert {:ok, first} = request(scope, %{request_key: key})
    assert {:ok, same} = request(scope, %{request_key: key})
    assert first.id == same.id
    assert {:error, _} = request(scope, %{request_key: key, mode: :audit})
    assert Ash.count!(ResultExport, authorize?: false) == 1

    assert [%Oban.Job{queue: "task_exports"}] =
             Oban.Testing.all_enqueued(Repo, worker: Tasks.Workers.ExportResults)
  end

  test "new draft exports fail before persistence and leave the source contract editable",
       scope do
    draft = ProjectsFixture.draft!(scope.context, scope.source)
    assert {:error, error} = request(%{scope | project: draft})
    assert Exception.message(error) =~ "project_not_activated"
    assert Ash.count!(ResultExport, authorize?: false) == 0
    assert Oban.Testing.all_enqueued(Repo, worker: Tasks.Workers.ExportResults) == []

    schema =
      Datasets.create_schema_version!(scope.context.org.id, scope.source.dataset.id,
        actor: scope.context.actor
      )

    root =
      Datasets.add_record_type!(scope.context.org.id, schema.id, "other", "Other",
        actor: scope.context.actor
      )

    Datasets.add_field_definition!(
      scope.context.org.id,
      root.id,
      "body",
      "Body",
      "text",
      "single",
      true,
      actor: scope.context.actor
    )

    schema =
      Datasets.publish_schema_version!(scope.context.org.id, schema.id, root.id,
        actor: scope.context.actor
      )

    repinned =
      ProjectsFixture.run!(scope.context, draft, :update_draft, %{schema_version_id: schema.id})

    assert repinned.schema_version_id == schema.id
  end

  test "an empty selection seals and publishes a verified header-only JSONL artifact", scope do
    {:ok, export} = request(scope)
    assert :ok = ResultExporting.process(export.id)
    ready = Ash.get!(ResultExport, export.id, authorize?: false)
    assert ready.state == :ready
    assert ready.record_count == 0
    assert %DateTime{} = ready.snapshot_at
    access = download!(scope, export.id)
    assert {:ok, bytes} = InMemory.read_sealed(access.read_access)
    assert [%{"kind" => "header", "format_version" => 1, "record_count" => "0"}] = jsonl(bytes)
    assert :ok = ResultExporting.process(export.id)
    assert Ash.get!(ResultExport, export.id, authorize?: false).asset_id == ready.asset_id
  end

  @tag rich: true
  test "default JSONL streams every typed kind with exact constraints and source context",
       scope do
    scope = submit!(scope)
    {:ok, export} = request(scope)
    sealed = ResultExporting.snapshot!(export.id)
    assert sealed.record_count > 150
    assert :ok = ResultExporting.process(export.id)
    {:ok, bytes} = InMemory.read_sealed(download!(scope, export.id).read_access)
    [header | rows] = jsonl(bytes)
    assert header["record_count"] == Integer.to_string(length(rows))

    assert Enum.map(rows, &{&1["kind"], &1["id"]}) ==
             Enum.sort(Enum.map(rows, &{&1["kind"], &1["id"]}))

    assert MapSet.new(rows, & &1["kind"]) ==
             MapSet.new(Snapshot.kinds(), &Atom.to_string/1)

    assert Enum.count(rows, &(&1["kind"] == "text_span")) == 150

    [decimal] =
      Enum.filter(rows, &(&1["kind"] == "question_response" and &1["family"] == "decimal"))

    assert decimal["decimal_value"] == "0.123456789123456789"

    definitions =
      rows |> Enum.filter(&(&1["kind"] == "question_definition")) |> Map.new(&{&1["id"], &1})

    rating = definitions[scope.source.form.question.id]
    assert rating["renderer"] == "stars"
    assert rating["integer_constraints"]["id"] == scope.source.form.bounds.id
    assert rating["integer_constraints"]["minimum"] == 1
    assert rating["text_constraints"] == nil

    assert definitions[scope.source.decimal.id]["decimal_constraints"]["minimum"] ==
             "0.123456789123456788"

    assert definitions[scope.source.spans.id]["annotation_constraints"]["source_convention"] ==
             "unicode_codepoints_zero_based_end_exclusive"

    assert Enum.any?(
             rows,
             &(&1["kind"] == "presentation_element" and &1["text"] == "Read all instructions")
           )

    assert Enum.count(rows, &(&1["kind"] == "dataset_value")) == 2
    [value | _] = Enum.filter(rows, &(&1["kind"] == "dataset_value"))
    assert value["text_value"] == String.duplicate("x", 200)
    refute String.contains?(bytes, "secret unbound")

    asset =
      Ash.get!(
        Asset,
        Ash.get!(ResultExport, export.id, authorize?: false).asset_id,
        authorize?: false
      )

    assert asset.sha256 == :crypto.hash(:sha256, bytes)
    assert asset.byte_size == byte_size(bytes)
  end

  test "sealed selection and review provenance survive correction and later submission", scope do
    scope = submit!(scope)

    [outcome] =
      QuestionResponse
      |> Ash.Query.filter(task_id == ^scope.attempt.task_id)
      |> Ash.read!(authorize?: false, page: false)

    [decision] =
      ReviewDecision
      |> Ash.Query.filter(question_response_id == ^outcome.id)
      |> Ash.read!(authorize?: false, page: false)

    {:ok, export} = request(scope)
    sealed = ResultExporting.snapshot!(export.id)

    Ash.create!(
      ReviewDecision,
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
        requester_id: scope.context.actor.id,
        request_key: Ash.UUID.generate()
      },
      action: :create_internal,
      authorize?: false
    )

    assert :ok = ResultExporting.process(export.id)
    {:ok, bytes} = InMemory.read_sealed(download!(scope, export.id).read_access)
    [header | rows] = jsonl(bytes)
    assert header["record_count"] == Integer.to_string(sealed.record_count)

    assert Enum.any?(
             rows,
             &(&1["kind"] == "question_response" and &1["effective_decision_id"] == decision.id)
           )

    assert Enum.any?(rows, &(&1["kind"] == "review_decision" and &1["id"] == decision.id))
    {:ok, new_export} = request(scope)
    assert ResultExporting.snapshot!(new_export.id).record_count == 0
    {:ok, audit} = request(scope, %{mode: :audit, evidence_kind: "review_decision"})
    assert ResultExporting.snapshot!(audit.id).record_count == 2
    assert :ok = ResultExporting.process(audit.id)
    {:ok, audit_bytes} = InMemory.read_sealed(download!(scope, audit.id).read_access)
    assert Enum.count(jsonl(audit_bytes)) == 3
  end

  @tag rich: true
  test "evidence and task ranges intersect without expanding related collections", scope do
    scope = submit!(scope)

    spans =
      TextSpan
      |> Ash.Query.sort(id: :asc)
      |> Ash.read!(authorize?: false, page: false)

    low = Enum.at(spans, 10).id
    high = Enum.at(spans, 120).id

    {:ok, export} =
      request(scope, %{
        evidence_kind: "text_span",
        evidence_id_from: low,
        evidence_id_to: high,
        task_id_from: scope.attempt.task_id,
        task_id_to: scope.attempt.task_id
      })

    assert ResultExporting.snapshot!(export.id).record_count == 111
    assert :ok = ResultExporting.process(export.id)
    {:ok, bytes} = InMemory.read_sealed(download!(scope, export.id).read_access)
    [_header | rows] = jsonl(bytes)
    assert Enum.count(rows) == 111
    assert Enum.all?(rows, &(&1["kind"] == "text_span" and &1["id"] >= low and &1["id"] <= high))

    {:ok, missing} =
      request(scope, %{
        evidence_kind: "text_span",
        task_id_from: "ffffffff-ffff-ffff-ffff-ffffffffffff"
      })

    assert ResultExporting.snapshot!(missing.id).record_count == 0
    assert {:error, _} = request(scope, %{evidence_id_from: low})

    assert {:error, _} =
             request(scope, %{
               evidence_kind: "text_span",
               evidence_id_from: high,
               evidence_id_to: low
             })
  end

  test "audit includes terminal offers and context while excluding unsent draft values", scope do
    scope = begin!(scope)
    save!(scope, scope.source.form.question, %{family: :integer, integer_value: 4}, 0)
    action!(Attempt, :release, attempt_scope(scope), scope.worker)
    {:ok, export} = request(scope, %{mode: :audit})
    assert :ok = ResultExporting.process(export.id)
    {:ok, bytes} = InMemory.read_sealed(download!(scope, export.id).read_access)
    [_header | rows] = jsonl(bytes)
    assert Enum.any?(rows, &(&1["kind"] == "attempt_question"))
    assert Enum.any?(rows, &(&1["kind"] == "dataset_value"))
    refute Enum.any?(rows, &(&1["kind"] in ["question_response", "review_decision"]))
  end

  defmodule UnavailableStorage do
    def enforces_byte_cap?, do: true
  end

  test "unavailable backend writes retain one protected pending identity and sealed retry",
       scope do
    {:ok, export} = request(scope)
    old = Application.fetch_env!(:quick_train, :assets)

    Application.put_env(
      :quick_train,
      :assets,
      Keyword.put(old, :storage_adapter, UnavailableStorage)
    )

    on_exit(fn -> Application.put_env(:quick_train, :assets, old) end)
    assert {:error, :export_storage_unavailable} = ResultExporting.process(export.id)
    failed = Ash.get!(ResultExport, export.id, authorize?: false)
    assert failed.state == :failed
    assert failed.asset_id == nil
    pending = Ash.get!(Asset, failed.pending_asset_id, authorize?: false)
    assert pending.result_export_id == export.id
    assert pending.state == :pending
    assert {:error, _} = download(scope, export.id)
    Application.put_env(:quick_train, :assets, old)
    assert :ok = ResultExporting.process(export.id)
    ready = Ash.get!(ResultExport, export.id, authorize?: false)
    assert ready.pending_asset_id == pending.id
    assert ready.snapshot_at == failed.snapshot_at

    assert Ash.get!(Asset, pending.id, authorize?: false).staging_expires_at ==
             pending.staging_expires_at
  end

  test "export hashes and IDs cannot bypass result authority before independent upload proof",
       scope do
    {:ok, export} = request(scope)
    assert :ok = ResultExporting.process(export.id)
    ready = Ash.get!(ResultExport, export.id, authorize?: false)
    asset = Ash.get!(Asset, ready.asset_id, authorize?: false)

    assert {:error, _} =
             Assets.get_asset(asset.id, asset.organization_id, actor: scope.context.actor)

    assert {:error, _} =
             Assets.get_asset_access(asset.id, asset.organization_id, actor: scope.context.actor)

    assert {:error, _} =
             Assets.finalize_asset(asset.id, asset.organization_id, actor: scope.context.actor)

    assert {:error, :invalid_asset} =
             Values.validate_assets(asset.organization_id, [
               %{family: :asset, value: asset.id}
             ])

    registration =
      Assets.register_asset!(
        asset.organization_id,
        Base.encode16(asset.sha256, case: :lower),
        asset.byte_size,
        asset.media_type,
        actor: scope.context.actor
      )

    refute registration.reused
    refute registration.asset.id == asset.id
    assert registration.asset.state == :pending

    assert {:error, _} =
             Assets.get_asset_access(asset.id, asset.organization_id, actor: scope.context.actor)

    {:ok, bytes} = InMemory.read_sealed(download!(scope, export.id).read_access)
    assert :ok = InMemory.put_staging(registration.upload_access, bytes)

    finalized =
      Assets.finalize_asset!(registration.asset.id, asset.organization_id,
        actor: scope.context.actor
      )

    assert finalized.canonical_asset.id == asset.id

    assert {:ok, _} =
             Assets.get_asset_access(asset.id, asset.organization_id, actor: scope.context.actor)

    assert :ok =
             Values.validate_assets(asset.organization_id, [
               %{family: :asset, value: asset.id}
             ])

    refute Map.has_key?(Map.from_struct(finalized.canonical_asset), :result_export_id)
  end

  test "result-only downloads and status recheck current membership and snapshot permission",
       scope do
    reader = Accounts.register_user!("result-export-only@example.test", "Results")
    membership = Organizations.add_member!(scope.context.org.id, reader.id)
    role = Authorization.create_role!(scope.context.org.id, "export-reader", "Reader")
    Authorization.assign_role!(scope.context.org.id, reader.id, role.id)

    capability =
      Authorization.create_capability!("tasks.results.read", "Results",
        upsert?: true,
        upsert_identity: :key,
        upsert_fields: []
      )

    Authorization.grant_capability!(role.id, capability.id)
    reader_scope = put_in(scope.context.actor, reader)
    {:ok, export} = request(reader_scope)
    assert :ok = ResultExporting.process(export.id)
    assert {:ok, _} = download(reader_scope, export.id)
    {:ok, waiting} = request(reader_scope)
    Organizations.deactivate_membership!(membership)
    assert {:error, _} = download(reader_scope, export.id)

    assert {:error, _} =
             ResultExport
             |> Ash.Query.for_read(
               :get_scoped,
               %{
                 organization_id: scope.context.org.id,
                 project_id: scope.project.id,
                 export_id: export.id
               },
               actor: reader
             )
             |> Ash.read_one()

    assert {:error, _} = ResultExporting.process(waiting.id)
    failed = Ash.get!(ResultExport, waiting.id, authorize?: false)
    assert failed.snapshot_at == nil
    assert failed.asset_id == nil
  end

  test "a submission committing after selection is absent from the sealed snapshot", scope do
    scope = begin!(scope)
    save!(scope, scope.source.form.question, %{family: :integer, integer_value: 4}, 0)
    parent = self()

    transaction =
      Elixir.Task.async(fn ->
        Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
          Ash.transact(
            Response,
            fn ->
              action!(Response, :submit, attempt_scope(scope), scope.worker)
              send(parent, :submission_uncommitted)

              receive do
                :commit -> :ok
              after
                10_000 -> raise "test synchronization timeout"
              end
            end,
            return_notifications?: true
          )
        end)
      end)

    assert_receive :submission_uncommitted, 5_000
    {:ok, export} = request(scope)
    sealed = ResultExporting.snapshot!(export.id)
    assert sealed.record_count == 0
    send(transaction.pid, :commit)
    assert {:ok, :ok, notifications} = Elixir.Task.await(transaction)
    Ash.Notifier.notify(notifications)
    assert :ok = ResultExporting.process(export.id)
    {:ok, newer} = request(scope)
    assert ResultExporting.snapshot!(newer.id).record_count > 0
  end

  test "concurrent workers converge without overwriting ready state or asset identity", scope do
    {:ok, export} = request(scope)
    ResultExporting.snapshot!(export.id)

    results = concurrently(List.duplicate(fn -> ResultExporting.process(export.id) end, 3))
    assert :ok in results

    ready = Ash.get!(ResultExport, export.id, authorize?: false)
    assert ready.state == :ready
    assert :ok = ResultExporting.process(export.id)
    assert Ash.get!(ResultExport, export.id, authorize?: false).asset_id == ready.asset_id
    assert Ash.count!(Asset, authorize?: false) == 1
  end

  defmodule NoAccessStorage do
    defdelegate enforces_byte_cap?(), to: InMemory
    defdelegate write_staging(key, chunks, cap, deadline_ms), to: InMemory
    defdelegate verify_and_publish(staging, sealed, facts, deadline), to: InMemory
    defdelegate verify_sealed(sealed, facts, deadline), to: InMemory
    def sealed_read_access(_key, _expiry), do: {:error, "private provider details"}
  end

  test "failure after byte publication retains its association and hides the artifact until retry",
       scope do
    {:ok, export} = request(scope)
    old = Application.fetch_env!(:quick_train, :assets)

    Application.put_env(
      :quick_train,
      :assets,
      Keyword.put(old, :storage_adapter, NoAccessStorage)
    )

    on_exit(fn -> Application.put_env(:quick_train, :assets, old) end)
    assert {:error, :export_access_unavailable} = ResultExporting.process(export.id)
    failed = Ash.get!(ResultExport, export.id, authorize?: false)
    assert failed.asset_id == nil
    assert failed.error_code == "export_access_unavailable"

    assert Path.wildcard(Path.join(System.tmp_dir!(), "quick_train_export_#{export.id}_*.jsonl")) ==
             []

    pending = Ash.get!(Asset, failed.pending_asset_id, authorize?: false)
    assert pending.state == :ready
    assert {:error, _} = download(scope, export.id)
    Application.put_env(:quick_train, :assets, old)
    assert :ok = ResultExporting.process(export.id)
    ready = Ash.get!(ResultExport, export.id, authorize?: false)
    assert ready.pending_asset_id == pending.id
    assert ready.asset_id == pending.id
    assert ready.snapshot_at == failed.snapshot_at
  end

  defmodule SlowWriteStorage do
    defdelegate enforces_byte_cap?(), to: InMemory

    def write_staging(key, chunks, cap, deadline_ms) do
      chunks =
        Stream.map(chunks, fn chunk ->
          Process.sleep(5_000)
          chunk
        end)

      InMemory.write_staging(key, chunks, cap, deadline_ms)
    end
  end

  test "write deadlines retain the protected pending identity and clean temporary output",
       scope do
    {:ok, export} = request(scope)
    old = Application.fetch_env!(:quick_train, :assets)

    config =
      old
      |> Keyword.put(:storage_adapter, SlowWriteStorage)
      |> Keyword.put(:publication_deadline_ms, 25)

    Application.put_env(:quick_train, :assets, config)
    on_exit(fn -> Application.put_env(:quick_train, :assets, old) end)
    started = System.monotonic_time(:millisecond)
    assert {:error, :storage_deadline_exceeded} = ResultExporting.process(export.id)
    assert System.monotonic_time(:millisecond) - started < 2_000
    failed = Ash.get!(ResultExport, export.id, authorize?: false)
    pending = Ash.get!(Asset, failed.pending_asset_id, authorize?: false)
    assert pending.state == :pending
    assert pending.result_export_id == export.id
    assert failed.asset_id == nil

    assert Path.wildcard(Path.join(System.tmp_dir!(), "quick_train_export_#{export.id}_*.jsonl")) ==
             []

    Application.put_env(:quick_train, :assets, old)
    assert :ok = ResultExporting.process(export.id)
    ready = Ash.get!(ResultExport, export.id, authorize?: false)
    assert ready.pending_asset_id == pending.id
    assert ready.snapshot_at == failed.snapshot_at

    assert Ash.get!(Asset, pending.id, authorize?: false).staging_expires_at ==
             pending.staging_expires_at
  end

  defp begin!(scope) do
    worker =
      Accounts.register_user!(
        "export-worker-#{System.unique_integer([:positive])}@example.test",
        "Worker"
      )

    attempt =
      action!(
        Attempt,
        :fetch,
        %{
          organization_id: scope.context.org.id,
          project_id: scope.project.id,
          request_key: Ash.UUID.generate()
        },
        worker
      ).attempt

    Map.merge(scope, %{worker: worker, attempt: attempt})
  end

  defp submit!(scope) do
    scope = begin!(scope)
    save!(scope, scope.source.form.question, %{family: :integer, integer_value: 4}, 0)

    if scope.source[:extra_questions] do
      inputs =
        TaskInput
        |> Ash.Query.filter(task_id == ^scope.attempt.task_id)
        |> Ash.read!(authorize?: false, page: false)

      input = hd(inputs)

      revision =
        Ash.get!(DatasetItemRevision, input.revision_id, authorize?: false)

      value =
        DatasetValue
        |> Ash.Query.filter(
          record_id == ^revision.root_record_id and field_definition_id == ^scope.source.field.id
        )
        |> Ash.read_one!(authorize?: false)

      save!(
        scope,
        scope.source.decimal,
        %{family: :decimal, decimal_value: "0.123456789123456789"},
        1
      )

      save!(
        scope,
        scope.source.choice,
        %{family: :static_single_choice, option_ids: [scope.source.option.id]},
        2
      )

      save!(
        scope,
        scope.source.ranking,
        %{
          family: :task_input_ranking,
          inputs:
            Enum.with_index(inputs, fn input, position ->
              %{task_input_id: input.id, position: position}
            end)
        },
        3
      )

      save!(
        scope,
        scope.source.spans,
        %{
          family: :text_spans,
          spans:
            for(
              i <- 0..149,
              do: %{
                task_input_id: input.id,
                source_value_id: value.id,
                label_id: scope.source.label.id,
                start: i,
                end: i + 1
              }
            )
        },
        4
      )
    end

    action!(Response, :submit, attempt_scope(scope), scope.worker)
    scope
  end

  defp save!(scope, question, answer, revision),
    do:
      action!(
        Response,
        :save_question,
        Map.merge(attempt_scope(scope), %{
          question_id: question.id,
          expected_revision: revision,
          answer: Map.put(answer, :outcome, :answered)
        }),
        scope.worker
      )

  defp attempt_scope(scope),
    do: %{
      organization_id: scope.context.org.id,
      project_id: scope.project.id,
      attempt_id: scope.attempt.id
    }

  defp action!(resource, action, args, actor),
    do: resource |> Ash.ActionInput.for_action(action, args, actor: actor) |> Ash.run_action!()

  defp rich_source!(context) do
    form = FormsFixture.rating!(context)

    FormsFixture.run!(InputSlotDefinition, :update_in_draft, context, %{
      version_id: form.version.id,
      id: form.slot.id,
      minimum: 2,
      maximum: 2
    })

    decimal =
      FormsFixture.add!(QuestionDefinition, context, form.version, %{
        key: "decimal",
        prompt: "Decimal",
        family: :decimal,
        renderer: :decimal_input
      })

    FormsFixture.add!(DecimalConstraints, context, form.version, %{
      question_id: decimal.id,
      minimum: "0.123456789123456788",
      maximum: "0.123456789123456790"
    })

    choice =
      FormsFixture.add!(QuestionDefinition, context, form.version, %{
        key: "choice",
        prompt: "Choice",
        family: :static_single_choice,
        renderer: :radio
      })

    option =
      FormsFixture.add!(QuestionOption, context, form.version, %{
        question_id: choice.id,
        key: "first",
        label: "First",
        position: 0
      })

    FormsFixture.add!(
      SelectionConstraints,
      context,
      form.version,
      %{question_id: choice.id, minimum: 1, maximum: 1}
    )

    FormsFixture.add!(QuestionOption, context, form.version, %{
      question_id: choice.id,
      key: "second",
      label: "Second",
      position: 1
    })

    ranking =
      FormsFixture.add!(QuestionDefinition, context, form.version, %{
        key: "ranking",
        prompt: "Rank",
        family: :task_input_ranking,
        renderer: :ranking,
        input_slot_id: form.slot.id
      })

    labels = FormsFixture.add!(LabelSet, context, form.version, %{key: "labels", name: "Labels"})

    label =
      FormsFixture.add!(Label, context, form.version, %{
        label_set_id: labels.id,
        key: "tag",
        text: "Tag",
        position: 0
      })

    spans =
      FormsFixture.add!(QuestionDefinition, context, form.version, %{
        key: "spans",
        prompt: "Spans",
        family: :text_spans,
        renderer: :text_spans
      })

    FormsFixture.add!(AnnotationConstraints, context, form.version, %{
      question_id: spans.id,
      source_requirement_id: form.field.id,
      label_set_id: labels.id,
      minimum: 0,
      maximum: 200
    })

    FormsFixture.add!(PresentationElement, context, form.version, %{
      kind: :instruction,
      position: 0,
      text: "Read all instructions"
    })

    for {question, i} <- Enum.with_index([decimal, choice, ranking, spans], 2),
        do:
          FormsFixture.add!(PresentationElement, context, form.version, %{
            kind: :question,
            position: i * 10,
            question_id: question.id
          })

    version =
      Forms.publish_form_version!(context.org.id, %{version_id: form.version.id},
        actor: context.actor
      )

    dataset = Datasets.create_dataset!(context.org.id, "items", "Items", actor: context.actor)
    schema = Datasets.create_schema_version!(context.org.id, dataset.id, actor: context.actor)

    root =
      Datasets.add_record_type!(context.org.id, schema.id, "item", "Item", actor: context.actor)

    field =
      Datasets.add_field_definition!(
        context.org.id,
        root.id,
        "body",
        "Body",
        "text",
        "single",
        true,
        actor: context.actor
      )

    Datasets.add_field_definition!(
      context.org.id,
      root.id,
      "private",
      "Private",
      "text",
      "single",
      false,
      actor: context.actor
    )

    schema =
      Datasets.publish_schema_version!(context.org.id, schema.id, root.id, actor: context.actor)

    revision =
      Datasets.put_item_revision!(
        context.org.id,
        dataset.id,
        schema.id,
        nil,
        "item",
        [
          %{field: "body", text: String.duplicate("x", 200)},
          %{field: "private", text: "secret unbound"}
        ],
        actor: context.actor
      ).revision

    revision2 =
      Datasets.put_item_revision!(
        context.org.id,
        dataset.id,
        schema.id,
        nil,
        "item2",
        [%{field: "body", text: String.duplicate("x", 200)}],
        actor: context.actor
      ).revision

    %{
      form: %{form | version: version},
      dataset: dataset,
      schema: schema,
      root: root,
      field: field,
      revisions: [revision, revision2],
      extra_questions: [decimal, choice, ranking, spans],
      decimal: decimal,
      choice: choice,
      option: option,
      ranking: ranking,
      spans: spans,
      label: label
    }
  end

  defp request(scope, attrs \\ %{}) do
    ResultExport
    |> Ash.ActionInput.for_action(
      :request_export,
      Map.merge(
        %{
          organization_id: scope.context.org.id,
          project_id: scope.project.id,
          request_key: Ash.UUID.generate(),
          mode: :accepted
        },
        attrs
      ),
      actor: scope.context.actor
    )
    |> Ash.run_action()
  end

  defp download(scope, id) do
    ResultExport
    |> Ash.ActionInput.for_action(
      :download_export,
      %{organization_id: scope.context.org.id, project_id: scope.project.id, export_id: id},
      actor: scope.context.actor
    )
    |> Ash.run_action()
  end

  defp download!(scope, id) do
    {:ok, result} = download(scope, id)
    result
  end

  defp jsonl(bytes), do: bytes |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)
end
