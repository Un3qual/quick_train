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
  alias QuickTrain.Tasks.Attempts.Attempt
  alias QuickTrain.Tasks.Exports.{ExportSelection, Jsonl, ResultExport}
  alias QuickTrain.Tasks.Responses.QuestionResponse
  alias QuickTrain.Tasks.Reviews.ReviewDecision
  alias QuickTrain.Tasks.TaskInput

  require Ash.Query

  setup tags do
    context =
      ProjectsFixture.context!(
        ~w(projects.read projects.manage forms.read forms.manage datasets.read datasets.manage tasks.results.read tasks.review assets.read assets.manage),
        "exports-#{System.unique_integer([:positive])}"
      )

    source_opts =
      if tags[:input_count],
        do: [
          item_count: tags.input_count,
          slot_maximum: tags.inputs_per_task,
          extra_bound_fields: tags[:extra_bound_fields] || 0
        ],
        else: []

    source =
      if tags[:rich],
        do: rich_source!(context),
        else: ProjectsFixture.source!(context, source_opts)

    project =
      ProjectsFixture.draft!(context, source,
        audience: :external_users,
        external_access: :open,
        review_mode: tags[:review_mode] || :automatic
      )

    QuickTrain.Projects.set_binding!(
      context.org.id,
      project.id,
      %{
        requirement_id: source.form.field.id,
        field_definition_id: source.field.id
      },
      actor: context.actor
    )

    for {requirement, field} <- Map.get(source, :extra_bindings, []) do
      QuickTrain.Projects.set_binding!(
        context.org.id,
        project.id,
        %{requirement_id: requirement.id, field_definition_id: field.id},
        actor: context.actor
      )
    end

    QuickTrain.Projects.set_slot_policy!(
      context.org.id,
      project.id,
      %{
        input_slot_id: source.form.slot.id,
        item_count: tags[:inputs_per_task] || if(tags[:rich], do: 2, else: 1),
        shuffle: false
      },
      actor: context.actor
    )

    count = tags[:inputs_per_task] || if(tags[:rich], do: 2, else: 1)

    for {items, position} <-
          source.revisions |> Enum.chunk_every(count) |> Enum.with_index() do
      Tasks.create_task!(
        context.org.id,
        project.id,
        %{
          position: position,
          inputs:
            Enum.with_index(items, fn item, index ->
              %{
                input_slot_id: source.form.slot.id,
                revision_id: item.id,
                position: (index + 1) * 10
              }
            end)
        },
        actor: context.actor
      )
    end

    project =
      QuickTrain.Projects.activate_project!(project, actor: context.actor)

    :ok = InMemory.reset()
    %{context: context, project: project, source: source}
  end

  @tag :rich
  test "a sealed export reproduces its bytes after a runtime restart", scope do
    scope = submit!(scope)
    {:ok, export} = request(scope)
    export = Tasks.seal_export_snapshot!(export.id, authorize?: false)
    path = Path.join(System.tmp_dir!(), "export_restart_#{export.id}")

    try do
      Jsonl.write!(export, path)

      code = """
      Application.ensure_all_started(:quick_train)
      Ecto.Adapters.SQL.Sandbox.checkout(QuickTrain.Repo, sandbox: false)
      export = Ash.get!(QuickTrain.Tasks.Exports.ResultExport, #{inspect(export.id)}, authorize?: false)
      QuickTrain.Tasks.Exports.Jsonl.write!(export, #{inspect(path <> "_restarted")})
      """

      {output, status} =
        System.cmd(
          "mix",
          ["run", "--no-start", "--no-compile", "--no-deps-check", "-e", code],
          stderr_to_stdout: true
        )

      assert status == 0, output
      assert File.read!(path) == File.read!(path <> "_restarted")
    after
      File.rm(path)
      File.rm(path <> "_restarted")
    end
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

  test "a snapshot stores one membership per outcome and rejects duplicate membership", scope do
    scope = submit!(scope)
    {:ok, export} = request(scope)
    Tasks.seal_export_snapshot!(export.id, authorize?: false)
    [selection] = Ash.read!(ExportSelection, authorize?: false, page: false)
    assert selection.question_response_id == Ash.read_one!(QuestionResponse, authorize?: false).id
    assert selection.decision_id == Ash.read_one!(ReviewDecision, authorize?: false).id

    assert {:error, _} =
             Ash.create(
               ExportSelection,
               Map.take(selection, [
                 :export_id,
                 :organization_id,
                 :project_id,
                 :form_version_id,
                 :task_id,
                 :question_id,
                 :question_response_id,
                 :decision_id
               ]),
               action: :create_internal,
               authorize?: false
             )
  end

  test "new draft exports fail before persistence and leave the source contract editable",
       scope do
    draft = ProjectsFixture.draft!(scope.context, scope.source)
    assert {:error, error} = request(%{scope | project: draft})
    assert Exception.message(error) =~ "project_not_activated"
    assert Ash.count!(ResultExport, authorize?: false) == 0
    assert Oban.Testing.all_enqueued(Repo, worker: Tasks.Workers.ExportResults) == []

    renamed =
      QuickTrain.Projects.configure_project!(draft, %{title: "Still draft"},
        actor: scope.context.actor
      )

    assert renamed.title == "Still draft"
    assert renamed.state == :draft
  end

  test "an empty selection seals and publishes a verified header-only JSONL artifact", scope do
    {:ok, export} = request(scope)
    assert :ok = QuickTrain.Tasks.process_result_export(export.id, authorize?: false)
    ready = Ash.get!(ResultExport, export.id, authorize?: false)
    assert ready.state == :ready
    assert ready.record_count == 0
    assert %DateTime{} = ready.snapshot_at
    access = download!(scope, export.id)
    assert {:ok, bytes} = InMemory.read_sealed(access.read_access)
    assert [%{"kind" => "header", "format_version" => 1, "record_count" => "0"}] = jsonl(bytes)
    assert :ok = QuickTrain.Tasks.process_result_export(export.id, authorize?: false)
    assert Ash.get!(ResultExport, export.id, authorize?: false).asset_id == ready.asset_id
  end

  @tag rich: true
  test "result JSONL streams nested answers with exact constraints and source context",
       scope do
    scope = submit!(scope)
    {:ok, export} = request(scope)
    sealed = QuickTrain.Tasks.seal_export_snapshot!(export.id, authorize?: false)
    assert sealed.record_count == Ash.count!(QuestionResponse, authorize?: false)
    assert :ok = QuickTrain.Tasks.process_result_export(export.id, authorize?: false)
    {:ok, bytes} = InMemory.read_sealed(download!(scope, export.id).read_access)
    [header | rows] = jsonl(bytes)
    assert header["record_count"] == Integer.to_string(length(rows))

    assert Enum.map(rows, &{&1["kind"], &1["id"]}) ==
             Enum.sort(Enum.map(rows, &{&1["kind"], &1["id"]}))

    assert Enum.all?(rows, &(&1["kind"] == "result"))
    assert Enum.sum_by(rows, &length(&1["text_spans"])) == 150
    assert Enum.any?(rows, &(&1["static_options"] != []))
    assert Enum.any?(rows, &(&1["input_answers"] != []))
    assert Enum.all?(rows, &(&1["review_decisions"] != []))

    [decimal] =
      Enum.filter(rows, &(&1["kind"] == "result" and &1["family"] == "decimal"))

    assert decimal["decimal_value"] == "0.123456789123456789"

    definitions =
      Map.new(header["questions"], &{&1["id"], &1})

    options = Map.new(definitions[scope.source.choice.id]["options"], &{&1["id"], &1})
    [choice] = Enum.filter(rows, &(&1["question_id"] == scope.source.choice.id))
    [answer] = choice["static_options"]
    assert options[answer["option_id"]]["label"] == "First"

    assert [label] = header["labels"]
    assert label["id"] == scope.source.label.id
    assert label["text"] == "Tag"

    assert [binding] = header["bindings"]
    assert binding["requirement"]["id"] == scope.source.form.field.id
    assert binding["requirement"]["input_slot_id"] == scope.source.form.slot.id
    assert binding["field"]["id"] == scope.source.field.id

    presentations = Ash.load!(scope.attempt, :input_presentations, authorize?: false)
    expected_order = Enum.map(presentations.input_presentations, &{&1.task_input_id, &1.position})

    for row <- rows do
      assert row["attempt"]["id"] == scope.attempt.id
      assert row["task"]["id"] == scope.attempt.task_id
      assert Enum.map(row["inputs"], &{&1["id"], &1["position"]}) == expected_order
    end

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
             header["presentation"],
             &(&1["text"] == "Read all instructions")
           )

    values = hd(rows)["inputs"] |> Enum.flat_map(& &1["values"])
    assert [value, _] = values
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

  @tag input_count: 100, inputs_per_task: 100
  test "one exported result retains every input at the published slot maximum", scope do
    submit!(scope)
    {:ok, export} = request(scope)
    assert :ok = QuickTrain.Tasks.process_result_export(export.id, authorize?: false)
    {:ok, bytes} = InMemory.read_sealed(download!(scope, export.id).read_access)
    [header, result] = jsonl(bytes)

    assert header["record_count"] == "1"
    rows = result["inputs"]
    assert length(rows) == length(scope.source.revisions)
    assert MapSet.size(MapSet.new(rows, & &1["id"])) == 100
    assert Enum.all?(rows, &match?([_], &1["values"]))

    assert MapSet.new(rows, & &1["revision_id"]) == MapSet.new(scope.source.revisions, & &1.id)
  end

  @tag input_count: 2, inputs_per_task: 2, extra_bound_fields: 63
  test "batched inputs retain every field at the published slot maximum without mixing records",
       scope do
    scope = submit!(scope)
    {:ok, export} = request(scope)
    assert :ok = Tasks.process_result_export(export.id, authorize?: false)
    {:ok, bytes} = InMemory.read_sealed(download!(scope, export.id).read_access)
    [_header, result] = jsonl(bytes)

    for {input, number} <- Enum.with_index(result["inputs"], 1) do
      assert Enum.map(input["values"], & &1["id"]) ==
               Enum.sort(Enum.map(input["values"], & &1["id"]))

      values = Map.new(input["values"], &{&1["field_key"], &1["text_value"]})
      assert map_size(values) == 64
      assert values["body"] == "Body #{number}"

      for index <- 1..63,
          do: assert(values["extra_#{index}"] == "extra_#{index} for item #{number}")
    end
  end

  @tag rich: true, review_mode: :manual
  test "receipts count mixed outcomes using the latest decisions", scope do
    scope = submit!(scope, skip_decimal: true)

    receipt = fn ->
      Tasks.attempt_receipt!(scope.context.org.id, scope.project.id, scope.attempt.id,
        actor: scope.worker
      )
      |> Map.take([:accepted, :pending, :rejected, :skipped])
    end

    assert receipt.() == %{accepted: 0, pending: 4, rejected: 0, skipped: 1}

    outcomes =
      QuestionResponse
      |> Ash.Query.filter(attempt_id == ^scope.attempt.id)
      |> Ash.read!(authorize?: false, page: false)
      |> Map.new(&{&1.question_id, &1})

    decide = fn question, verdict, predecessor ->
      Tasks.decide_question!(
        scope.context.org.id,
        scope.project.id,
        %{
          question_response_id: outcomes[question.id].id,
          verdict: verdict,
          request_key: Ash.UUID.generate(),
          expected_predecessor_id: predecessor,
          reason: "Reviewed"
        },
        actor: scope.context.actor
      )
    end

    accepted = decide.(scope.source.form.question, :accept, nil)
    decide.(scope.source.choice, :reject, nil)
    assert receipt.() == %{accepted: 1, pending: 2, rejected: 1, skipped: 1}

    decide.(scope.source.form.question, :reject, accepted.id)
    assert receipt.() == %{accepted: 0, pending: 2, rejected: 2, skipped: 1}
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
    sealed = QuickTrain.Tasks.seal_export_snapshot!(export.id, authorize?: false)

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

    assert :ok = QuickTrain.Tasks.process_result_export(export.id, authorize?: false)
    {:ok, bytes} = InMemory.read_sealed(download!(scope, export.id).read_access)
    [header | rows] = jsonl(bytes)
    assert header["record_count"] == Integer.to_string(sealed.record_count)

    assert Enum.any?(
             rows,
             &(&1["kind"] == "result" and &1["effective_decision_id"] == decision.id)
           )

    assert Enum.any?(Enum.flat_map(rows, & &1["review_decisions"]), &(&1["id"] == decision.id))
    {:ok, new_export} = request(scope)

    assert QuickTrain.Tasks.seal_export_snapshot!(new_export.id, authorize?: false).record_count ==
             0

    {:ok, audit} = request(scope, %{mode: :audit})
    QuickTrain.Tasks.seal_export_snapshot!(audit.id, authorize?: false)
    current = Ash.load!(outcome, :effective_decision, authorize?: false).effective_decision

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
        verdict: :accept,
        number: 3,
        predecessor_id: current.id,
        requester_id: scope.context.actor.id,
        request_key: Ash.UUID.generate(),
        reason: "Later correction"
      },
      action: :create_internal,
      authorize?: false
    )

    assert :ok = QuickTrain.Tasks.process_result_export(audit.id, authorize?: false)
    {:ok, audit_bytes} = InMemory.read_sealed(download!(scope, audit.id).read_access)
    [_header, result] = jsonl(audit_bytes)
    assert [_, _] = result["review_decisions"]
  end

  test "audit excludes terminal drafts and their unused context", scope do
    scope = begin!(scope)
    save!(scope, scope.source.form.question, %{family: :integer, integer_value: 4}, 0)
    Tasks.release_attempt!(scope.attempt, actor: scope.worker)
    {:ok, export} = request(scope, %{mode: :audit})
    assert :ok = QuickTrain.Tasks.process_result_export(export.id, authorize?: false)
    {:ok, bytes} = InMemory.read_sealed(download!(scope, export.id).read_access)
    [_header | rows] = jsonl(bytes)
    assert rows == []
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

    assert {:error,
            %Ash.Error.Invalid{
              errors: [%QuickTrain.DatasetAssetError{category: :export_storage_unavailable}]
            }} =
             QuickTrain.Tasks.process_result_export(export.id, authorize?: false)

    failed = Ash.get!(ResultExport, export.id, authorize?: false)
    assert failed.state == :failed
    assert failed.asset_id == nil
    pending = Ash.get!(Asset, failed.pending_asset_id, authorize?: false)
    assert pending.result_export_id == export.id
    assert pending.state == :pending
    assert {:error, _} = download(scope, export.id)
    Application.put_env(:quick_train, :assets, old)
    assert :ok = QuickTrain.Tasks.process_result_export(export.id, authorize?: false)
    ready = Ash.get!(ResultExport, export.id, authorize?: false)
    assert ready.pending_asset_id == pending.id
    assert ready.snapshot_at == failed.snapshot_at

    assert Ash.get!(Asset, pending.id, authorize?: false).staging_expires_at ==
             pending.staging_expires_at
  end

  defmodule CorruptWriteStorage do
    defdelegate enforces_byte_cap?(), to: InMemory
    defdelegate verify_and_publish(staging, sealed, facts, deadline), to: InMemory

    def write_staging(key, _chunks, cap, deadline_ms),
      do: InMemory.write_staging(key, ["corrupt"], cap, deadline_ms)
  end

  test "a failed upload is replaced before expiry without changing the sealed snapshot", scope do
    {:ok, export} = request(scope)
    old = Application.fetch_env!(:quick_train, :assets)
    on_exit(fn -> Application.put_env(:quick_train, :assets, old) end)

    Application.put_env(
      :quick_train,
      :assets,
      Keyword.put(old, :storage_adapter, CorruptWriteStorage)
    )

    assert {:error, _error} = Tasks.process_result_export(export.id, authorize?: false)
    failed = Ash.get!(ResultExport, export.id, authorize?: false)
    asset = Ash.get!(Asset, failed.pending_asset_id, authorize?: false)
    assert asset.state == :failed
    assert asset.failure_reason == "content_mismatch"
    assert DateTime.after?(asset.staging_expires_at, DateTime.utc_now())
    assert {:error, _error} = download(scope, export.id)

    Application.put_env(:quick_train, :assets, old)
    submit!(scope)

    assert :ok = Tasks.process_result_export(export.id, authorize?: false)
    ready = Ash.get!(ResultExport, export.id, authorize?: false)
    replacement = Ash.get!(Asset, ready.asset_id, authorize?: false)
    assert ready.state == :ready
    assert ready.snapshot_at == failed.snapshot_at
    assert ready.record_count == 0
    assert replacement.id != asset.id
    assert replacement.result_export_id == export.id
    assert Ash.get!(Asset, asset.id, authorize?: false).result_export_id == export.id

    {:ok, bytes} = InMemory.read_sealed(download!(scope, export.id).read_access)
    assert [%{"kind" => "header", "record_count" => "0"}] = jsonl(bytes)
    assert :crypto.hash(:sha256, bytes) == asset.sha256
  end

  for state <- [:pending, :failed] do
    @tag expired_asset_state: state
    test "an expired #{state} upload is replaced without changing the sealed snapshot", scope do
      {:ok, export} = request(scope)
      old = Application.fetch_env!(:quick_train, :assets)
      on_exit(fn -> Application.put_env(:quick_train, :assets, old) end)

      Application.put_env(
        :quick_train,
        :assets,
        Keyword.put(old, :staging_lifetime_seconds, 0)
      )

      assert {:error, error} = Tasks.process_result_export(export.id, authorize?: false)
      assert Exception.message(error) =~ "staging_expired"
      failed = Ash.get!(ResultExport, export.id, authorize?: false)
      pending = Ash.get!(Asset, failed.pending_asset_id, authorize?: false)

      if scope.expired_asset_state == :failed do
        finalized = Assets.finalize_asset!(pending.id, pending.organization_id, authorize?: false)
        assert finalized.asset.state == :failed
      end

      Application.put_env(:quick_train, :assets, old)
      submit!(scope)

      assert :ok = Tasks.process_result_export(export.id, authorize?: false)
      ready = Ash.get!(ResultExport, export.id, authorize?: false)
      replacement = Ash.get!(Asset, ready.pending_asset_id, authorize?: false)
      assert ready.state == :ready
      assert ready.snapshot_at == failed.snapshot_at
      assert ready.record_count == 0
      assert replacement.id != pending.id
      assert replacement.result_export_id == export.id
      assert replacement.sha256 == pending.sha256

      {:ok, bytes} = InMemory.read_sealed(download!(scope, export.id).read_access)
      assert [%{"kind" => "header", "record_count" => "0"}] = jsonl(bytes)
      assert :crypto.hash(:sha256, bytes) == pending.sha256
      assert :ok = Tasks.process_result_export(export.id, authorize?: false)
      assert Ash.get!(ResultExport, export.id, authorize?: false).asset_id == ready.asset_id
    end
  end

  test "export hashes and IDs cannot bypass result authority before independent upload proof",
       scope do
    {:ok, export} = request(scope)
    assert :ok = QuickTrain.Tasks.process_result_export(export.id, authorize?: false)
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
    assert :ok = QuickTrain.Tasks.process_result_export(export.id, authorize?: false)
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

    assert {:error, _} = QuickTrain.Tasks.process_result_export(waiting.id, authorize?: false)
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
            Attempt,
            fn ->
              Tasks.submit_response!(scope.attempt, actor: scope.worker)
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
    sealed = QuickTrain.Tasks.seal_export_snapshot!(export.id, authorize?: false)
    assert sealed.record_count == 0
    send(transaction.pid, :commit)
    assert {:ok, :ok, notifications} = Elixir.Task.await(transaction)
    Ash.Notifier.notify(notifications)
    assert :ok = QuickTrain.Tasks.process_result_export(export.id, authorize?: false)
    {:ok, newer} = request(scope)
    assert QuickTrain.Tasks.seal_export_snapshot!(newer.id, authorize?: false).record_count > 0
  end

  test "concurrent workers converge without overwriting ready state or asset identity", scope do
    {:ok, export} = request(scope)
    QuickTrain.Tasks.seal_export_snapshot!(export.id, authorize?: false)

    results =
      concurrently(
        List.duplicate(
          fn -> QuickTrain.Tasks.process_result_export(export.id, authorize?: false) end,
          3
        )
      )

    assert :ok in results

    ready = Ash.get!(ResultExport, export.id, authorize?: false)
    assert ready.state == :ready
    assert :ok = QuickTrain.Tasks.process_result_export(export.id, authorize?: false)
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

    assert {:error,
            %Ash.Error.Invalid{
              errors: [%QuickTrain.DatasetAssetError{category: :export_access_unavailable}]
            }} =
             QuickTrain.Tasks.process_result_export(export.id, authorize?: false)

    failed = Ash.get!(ResultExport, export.id, authorize?: false)
    assert failed.asset_id == nil
    assert failed.error_code == "export_access_unavailable"

    assert Path.wildcard(Path.join(System.tmp_dir!(), "quick_train_export_#{export.id}_*.jsonl")) ==
             []

    pending = Ash.get!(Asset, failed.pending_asset_id, authorize?: false)
    assert pending.state == :ready
    assert {:error, _} = download(scope, export.id)
    Application.put_env(:quick_train, :assets, old)
    assert :ok = QuickTrain.Tasks.process_result_export(export.id, authorize?: false)
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

    assert {:error,
            %Ash.Error.Invalid{
              errors: [%QuickTrain.DatasetAssetError{category: :storage_deadline_exceeded}]
            }} =
             QuickTrain.Tasks.process_result_export(export.id, authorize?: false)

    assert System.monotonic_time(:millisecond) - started < 2_000
    failed = Ash.get!(ResultExport, export.id, authorize?: false)
    pending = Ash.get!(Asset, failed.pending_asset_id, authorize?: false)
    assert pending.state == :pending
    assert pending.result_export_id == export.id
    assert failed.asset_id == nil

    assert Path.wildcard(Path.join(System.tmp_dir!(), "quick_train_export_#{export.id}_*.jsonl")) ==
             []

    Application.put_env(:quick_train, :assets, old)
    assert :ok = QuickTrain.Tasks.process_result_export(export.id, authorize?: false)
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

  defp submit!(scope, opts \\ []) do
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
        if(opts[:skip_decimal],
          do: %{outcome: :skipped, family: :decimal, reason: "Cannot assess"},
          else: %{family: :decimal, decimal_value: "0.123456789123456789"}
        ),
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

    Tasks.submit_response!(scope.attempt, actor: scope.worker)
    scope
  end

  defp save!(scope, question, answer, revision),
    do:
      Tasks.save_question!(
        scope.attempt,
        %{
          question_id: question.id,
          expected_revision: revision,
          answer: Map.put_new(answer, :outcome, :answered)
        },
        actor: scope.worker
      )

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
    args =
      Map.merge(
        %{
          organization_id: scope.context.org.id,
          project_id: scope.project.id,
          request_key: Ash.UUID.generate(),
          mode: :accepted
        },
        attrs
      )

    Tasks.request_result_export(
      args.organization_id,
      args.project_id,
      args.request_key,
      args.mode,
      actor: scope.context.actor
    )
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
