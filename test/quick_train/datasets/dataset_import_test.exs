defmodule QuickTrain.Datasets.DatasetImportTest do
  use QuickTrain.DataCase, async: false
  use Oban.Testing, repo: QuickTrain.Repo

  require Ash.Query

  alias QuickTrain.{Accounts, Datasets}
  alias QuickTrain.Datasets.{DatasetImport, DatasetImportRow, DatasetItem, DatasetRecord}

  alias QuickTrain.Datasets.Workers.{
    ExpiredOpenImportCleanup,
    ImportRowTerminalization,
    ProcessImportRow
  }

  defmodule FailingScheduler do
    def enqueue(_row_id), do: {:error, :simulated_schedule_failure}
  end

  setup do
    manager = Accounts.register_user!("import-manager@example.test", "Import Manager")
    graph = Accounts.bootstrap_first_manager!(manager.id, "import-org", "Import Org")
    Datasets.grant_dataset_and_asset_capabilities!(graph.organization.id, manager.id)

    dataset =
      Datasets.create_dataset!(graph.organization.id, "customers", "Customers", actor: manager)

    schema = published_schema(graph.organization.id, dataset.id, manager)

    %{manager: manager, organization: graph.organization, dataset: dataset, schema: schema}
  end

  test "open is idempotent and changed immutable parameters conflict", context do
    first = open!(context, "batch-1")
    retry = open!(context, "batch-1")
    assert retry.id == first.id
    assert first.phase == :open
    assert DateTime.after?(first.open_expires_at, DateTime.utc_now())

    next_schema = published_schema(context.organization.id, context.dataset.id, context.manager)

    assert {:error, error} =
             Datasets.open_import(
               context.organization.id,
               context.dataset.id,
               next_schema.id,
               "batch-1",
               actor: context.manager
             )

    assert Exception.message(error) =~ "idempotency_conflict"
    assert Ash.count!(DatasetImport, authorize?: false) == 1
  end

  test "append stages a normalized candidate and equivalent retry converges", context do
    import = open!(context, "append-valid")

    first =
      append!(context, import, "row-1", "customer-1", 0, [
        %{field: "name", text: "Alice"},
        %{field: "balance", decimal: "1.00"},
        %{field: "joined_at", utc_datetime: "2026-01-02T03:04:05+02:00"}
      ])

    assert first.outcome == :pending
    assert first.candidate_record_id
    assert is_nil(first.item_revision_id)

    retry =
      append!(context, import, "row-1", "customer-1", 0, [
        %{field: "joined_at", utc_datetime: "2026-01-02T01:04:05Z"},
        %{field: "balance", decimal: "1.0"},
        %{field: "name", text: "Alice"}
      ])

    assert retry.id == first.id
    assert retry.fingerprint == first.fingerprint
    assert Ash.count!(DatasetImportRow, authorize?: false) == 1
    assert Ash.count!(DatasetRecord, authorize?: false) == 1
    assert Ash.count!(DatasetItem, authorize?: false) == 0
  end

  test "domain-invalid rows retain sanitized provenance without a partial candidate", context do
    import = open!(context, "append-invalid")

    row =
      append!(context, import, "missing-name", nil, 0, [
        %{field: "balance", decimal: "2"}
      ])

    assert row.outcome == :failed
    assert row.error_code == "required_missing:name"
    assert is_nil(row.candidate_record_id)
    assert Ash.count!(DatasetRecord, authorize?: false) == 0

    assert {:error, malformed} =
             Datasets.append_import_row(
               context.organization.id,
               import.id,
               "malformed",
               nil,
               1,
               [%{field: "balance", decimal: "not-a-decimal"}],
               actor: context.manager
             )

    assert Exception.message(malformed) =~ "malformed_decimal"
    assert Ash.count!(DatasetImportRow, authorize?: false) == 1
  end

  test "row key, source position, and external key identities fail closed", context do
    import = open!(context, "append-identities")
    values = [%{field: "name", text: "Alice"}]
    first = append!(context, import, "row-1", "customer-1", 0, values)

    assert {:error, row_key_error} =
             Datasets.append_import_row(
               context.organization.id,
               import.id,
               "row-1",
               "customer-1",
               1,
               values,
               actor: context.manager
             )

    assert Exception.message(row_key_error) =~ "idempotency_conflict"

    assert {:error, source_error} =
             Datasets.append_import_row(
               context.organization.id,
               import.id,
               "row-2",
               "customer-2",
               0,
               values,
               actor: context.manager
             )

    assert Exception.message(source_error) =~ "idempotency_conflict"

    assert {:error, external_error} =
             Datasets.append_import_row(
               context.organization.id,
               import.id,
               "row-3",
               "customer-1",
               2,
               values,
               actor: context.manager
             )

    assert Exception.message(external_error) =~ "duplicate_external_key"
    assert Ash.count!(DatasetImportRow, authorize?: false) == 1
    assert Ash.get!(DatasetImportRow, first.id, authorize?: false).id == first.id
  end

  test "structural limits reject input before row identity reservation", context do
    import = open!(context, "limits")
    original = Application.fetch_env!(:quick_train, :dataset_imports)

    limited =
      original
      |> Keyword.put(:max_fields_per_row, 1)
      |> Keyword.put(:max_text_bytes, 3)

    Application.put_env(:quick_train, :dataset_imports, limited)
    on_exit(fn -> Application.put_env(:quick_train, :dataset_imports, original) end)

    assert {:error, field_error} =
             Datasets.append_import_row(
               context.organization.id,
               import.id,
               "too-many",
               nil,
               0,
               [%{field: "name", text: "A"}, %{field: "balance", decimal: "1"}],
               actor: context.manager
             )

    assert Exception.message(field_error) =~ "row_field_limit_exceeded"

    assert {:error, text_error} =
             Datasets.append_import_row(
               context.organization.id,
               import.id,
               "too-long",
               nil,
               1,
               [%{field: "name", text: "four"}],
               actor: context.manager
             )

    assert Exception.message(text_error) =~ "row_scalar_limit_exceeded"
    assert Ash.count!(DatasetImportRow, authorize?: false) == 0
  end

  test "a valid keyless row reserves no item before processing", context do
    import = open!(context, "keyless")
    row = append!(context, import, "row-keyless", nil, 0, [%{field: "name", text: "Keyless"}])

    assert row.outcome == :pending
    assert Ash.count!(DatasetItem, authorize?: false) == 0
  end

  test "finalization atomically seals, schedules pending rows, and derives progress", context do
    import = open!(context, "finalize")

    pending =
      append!(context, import, "valid", "customer-1", 0, [%{field: "name", text: "Alice"}])

    failed = append!(context, import, "invalid", nil, 1, [%{field: "balance", decimal: "1"}])
    assert failed.outcome == :failed

    sealed = Datasets.finalize_import!(context.organization.id, import.id, actor: context.manager)
    assert sealed.phase == :sealed
    assert %DateTime{} = sealed.sealed_at

    assert [%Oban.Job{args: %{"row_id" => pending_id}}] =
             all_enqueued(worker: ProcessImportRow)

    assert pending_id == pending.id
    retry = Datasets.finalize_import!(context.organization.id, import.id, actor: context.manager)
    assert retry.id == sealed.id
    assert [%Oban.Job{}] = all_enqueued(worker: ProcessImportRow)

    before = Datasets.inspect_import!(context.organization.id, import.id, actor: context.manager)
    assert before.lifecycle == :pending
    assert {before.row_count, before.pending, before.failed} == {2, 1, 1}

    assert :ok = perform_job(ProcessImportRow, %{"row_id" => pending.id})
    completed = Ash.get!(DatasetImportRow, pending.id, authorize?: false)
    assert completed.outcome == :succeeded
    assert completed.item_revision_id

    revision =
      Ash.get!(QuickTrain.Datasets.DatasetItemRevision, completed.item_revision_id,
        authorize?: false
      )

    assert revision.root_record_id == pending.candidate_record_id
    assert Ash.count!(DatasetRecord, authorize?: false) == 1

    assert {:ok, :skipped} =
             Datasets.cleanup_expired_import(
               import.id,
               %{now: DateTime.add(import.open_expires_at, 1, :second)},
               authorize?: false
             )

    assert Ash.get!(DatasetRecord, revision.root_record_id, authorize?: false)

    assert :ok = perform_job(ProcessImportRow, %{"row_id" => pending.id})
    assert Ash.count!(QuickTrain.Datasets.DatasetItemRevision, authorize?: false) == 1

    after_processing =
      Datasets.inspect_import!(context.organization.id, import.id, actor: context.manager)

    assert after_processing.lifecycle == :partially_failed

    assert {after_processing.pending, after_processing.succeeded, after_processing.failed} ==
             {0, 1, 1}

    assert {:error, append_error} =
             Datasets.append_import_row(
               context.organization.id,
               import.id,
               "too-late",
               nil,
               2,
               [%{field: "name", text: "Late"}],
               actor: context.manager
             )

    assert Exception.message(append_error) =~ "import_not_open"
  end

  test "keyless processing uses the import row UUID as stable item identity", context do
    import = open!(context, "keyless-processing")
    row = append!(context, import, "keyless", nil, 0, [%{field: "name", text: "Keyless"}])
    Datasets.finalize_import!(context.organization.id, import.id, actor: context.manager)

    assert :ok = perform_job(ProcessImportRow, %{"row_id" => row.id})
    assert Ash.get!(DatasetItem, row.id, authorize?: false).id == row.id
  end

  test "unchanged imports retain their candidate while referencing the existing revision",
       context do
    [first, unchanged] =
      for key <- ["first-import", "unchanged-import"] do
        import = open!(context, key)

        row =
          append!(context, import, "same-row", "same-customer", 0, [
            %{field: "name", text: "Same"}
          ])

        Datasets.finalize_import!(context.organization.id, import.id, actor: context.manager)
        assert :ok = perform_job(ProcessImportRow, %{"row_id" => row.id})
        Ash.get!(DatasetImportRow, row.id, authorize?: false)
      end

    assert first.outcome == :succeeded
    assert unchanged.outcome == :unchanged
    assert unchanged.item_revision_id == first.item_revision_id
    refute unchanged.candidate_record_id == first.candidate_record_id
    assert Ash.count!(DatasetRecord, authorize?: false) == 2
  end

  @tag :committed_db
  test "destroying a referenced candidate rolls back its child deletions", context do
    import = open!(context, "protected-candidate")
    row = append!(context, import, "protected", nil, 0, [%{field: "name", text: "Retain"}])
    Datasets.finalize_import!(context.organization.id, import.id, actor: context.manager)
    assert :ok = perform_job(ProcessImportRow, %{"row_id" => row.id})
    record = Ash.get!(DatasetRecord, row.candidate_record_id, authorize?: false)

    assert {:error, _error} = Ash.destroy(record, action: :destroy_internal, authorize?: false)

    record = Ash.load!(record, [values: :text_value], authorize?: false)
    assert [%{text_value: %{value: "Retain"}}] = record.values
  end

  test "a row-job scheduling failure rolls sealing back atomically", context do
    import = open!(context, "schedule-rollback")
    append!(context, import, "row", "customer", 0, [%{field: "name", text: "Alice"}])

    Application.put_env(:quick_train, :dataset_import_row_scheduler, FailingScheduler)
    on_exit(fn -> Application.delete_env(:quick_train, :dataset_import_row_scheduler) end)

    assert {:error, error} =
             Datasets.finalize_import(
               context.organization.id,
               import.id,
               actor: context.manager
             )

    assert Exception.message(error) =~ "simulated_schedule_failure"
    persisted = Ash.get!(DatasetImport, import.id, authorize?: false)
    assert persisted.phase == :open
    assert is_nil(persisted.sealed_at)
    assert all_enqueued(worker: ProcessImportRow) == []
  end

  test "terminal-job reconciliation fails a still-pending row without a revision", context do
    import = open!(context, "terminalize")

    row =
      append!(context, import, "terminal", "customer-terminal", 0, [
        %{field: "name", text: "Terminal"}
      ])

    Datasets.finalize_import!(context.organization.id, import.id, actor: context.manager)

    [job] = all_enqueued(worker: ProcessImportRow)
    assert :ok = Oban.cancel_job(job.id)
    assert :ok = perform_job(ImportRowTerminalization, %{})

    terminal = Ash.get!(DatasetImportRow, row.id, authorize?: false)
    assert terminal.outcome == :failed
    assert terminal.error_code == "processing_retries_exhausted"
    assert is_nil(terminal.item_revision_id)
    assert Ash.count!(DatasetItem, authorize?: false) == 0

    config = Application.fetch_env!(:quick_train, Oban)
    assert config[:pruner][:max_age] == {1, :day}
    assert {"*/10 * * * *", ImportRowTerminalization} in config[:cron][:crontab]
  end

  test "terminal-job reconciliation is not starved by older jobs for terminal rows", context do
    old_import = open!(context, "terminalize-old")

    old_row =
      append!(context, old_import, "already-terminal", nil, 0, [
        %{field: "balance", decimal: "1"}
      ])

    assert old_row.outcome == :failed

    for _index <- 1..100 do
      %{row_id: old_row.id}
      |> ProcessImportRow.new(state: "cancelled")
      |> QuickTrain.Repo.insert!()
    end

    target_import = open!(context, "terminalize-target")

    target_row =
      append!(context, target_import, "target", "customer-target", 0, [
        %{field: "name", text: "Target"}
      ])

    Datasets.finalize_import!(
      context.organization.id,
      target_import.id,
      actor: context.manager
    )

    [target_job] = all_enqueued(worker: ProcessImportRow)
    assert :ok = Oban.cancel_job(target_job.id)
    assert :ok = perform_job(ImportRowTerminalization, %{})

    terminal = Ash.get!(DatasetImportRow, target_row.id, authorize?: false)
    assert terminal.outcome == :failed
    assert terminal.error_code == "processing_retries_exhausted"
  end

  test "terminal-job reconciliation continues after a full bounded page", context do
    backlog_import = open!(context, "terminalize-backlog")

    backlog_rows =
      for source_position <- 0..99 do
        append!(
          context,
          backlog_import,
          "backlog-#{source_position}",
          "backlog-customer-#{source_position}",
          source_position,
          [%{field: "name", text: "Backlog #{source_position}"}]
        )
      end

    Datasets.finalize_import!(
      context.organization.id,
      backlog_import.id,
      actor: context.manager
    )

    for job <- all_enqueued(worker: ProcessImportRow), do: :ok = Oban.cancel_job(job.id)

    target_import = open!(context, "terminalize-after-backlog")

    target_row =
      append!(context, target_import, "target", "customer-after-backlog", 0, [
        %{field: "name", text: "Target"}
      ])

    Datasets.finalize_import!(
      context.organization.id,
      target_import.id,
      actor: context.manager
    )

    [target_job] = all_enqueued(worker: ProcessImportRow, args: %{row_id: target_row.id})
    assert :ok = Oban.cancel_job(target_job.id)

    assert {:snooze, 1} = perform_job(ImportRowTerminalization, %{})

    assert Enum.all?(
             backlog_rows,
             &(Ash.get!(DatasetImportRow, &1.id, authorize?: false).outcome == :failed)
           )

    assert Ash.get!(DatasetImportRow, target_row.id, authorize?: false).outcome == :pending

    assert :ok = perform_job(ImportRowTerminalization, %{})
    assert Ash.get!(DatasetImportRow, target_row.id, authorize?: false).outcome == :failed
  end

  @tag :committed_db
  test "concurrent row workers serialize revisions for one unseen external key", context do
    first_import = open!(context, "concurrent-first")
    second_import = open!(context, "concurrent-second")

    first =
      append!(context, first_import, "first", "shared", 0, [%{field: "name", text: "First"}])

    second =
      append!(context, second_import, "second", "shared", 0, [%{field: "name", text: "Second"}])

    Datasets.finalize_import!(context.organization.id, first_import.id, actor: context.manager)
    Datasets.finalize_import!(context.organization.id, second_import.id, actor: context.manager)

    results =
      concurrently(
        for row <- [first, second],
            do: fn -> Datasets.process_import_row(row.id, authorize?: false) end
      )

    # A first-item uniqueness race rolls back the losing row transaction. Oban
    # retries that still-pending row using the now-committed stable item.
    Enum.each(results, fn
      {:ok, _row} ->
        :ok

      {:error, error} ->
        assert QuickTrain.AshError.constraint?(error, ["dataset_items_dataset_external_key_index"])
    end)

    for row <- [first, second] do
      assert :ok = perform_job(ProcessImportRow, %{"row_id" => row.id})
      assert Ash.get!(DatasetImportRow, row.id, authorize?: false).outcome == :succeeded
    end

    [item] = Ash.read!(QuickTrain.Datasets.DatasetItem, authorize?: false)

    revisions =
      QuickTrain.Datasets.DatasetItemRevision
      |> Ash.Query.filter(item_id == ^item.id)
      |> Ash.Query.sort(revision_number: :asc)
      |> Ash.read!(authorize?: false)

    assert Enum.map(revisions, & &1.revision_number) == [1, 2]
  end

  test "expired open cleanup deletes candidates and releases batch identity", context do
    original = Application.fetch_env!(:quick_train, :dataset_imports)

    Application.put_env(
      :quick_train,
      :dataset_imports,
      Keyword.put(original, :open_lifetime_seconds, 1)
    )

    on_exit(fn -> Application.put_env(:quick_train, :dataset_imports, original) end)

    import = open!(context, "expire")

    row =
      append!(context, import, "expire-row", nil, 0, [
        %{field: "name", text: "Expire"},
        %{field: "balance", decimal: "1.2"},
        %{field: "joined_at", utc_datetime: "2026-01-02T03:04:05Z"}
      ])

    assert row.candidate_record_id
    Process.sleep(1_050)

    assert :ok = perform_job(ExpiredOpenImportCleanup, %{})
    assert is_nil(Ash.get!(DatasetImport, import.id, authorize?: false, not_found_error?: false))
    assert is_nil(Ash.get!(DatasetImportRow, row.id, authorize?: false, not_found_error?: false))

    assert is_nil(
             Ash.get!(DatasetRecord, row.candidate_record_id,
               authorize?: false,
               not_found_error?: false
             )
           )

    replacement = open!(context, "expire")
    refute replacement.id == import.id

    config = Application.fetch_env!(:quick_train, Oban)
    assert {"23 * * * *", ExpiredOpenImportCleanup} in config[:cron][:crontab]
  end

  defp open!(context, key) do
    Datasets.open_import!(
      context.organization.id,
      context.dataset.id,
      context.schema.id,
      key,
      actor: context.manager
    )
  end

  defp append!(context, import, row_key, external_key, source_position, values) do
    Datasets.append_import_row!(
      context.organization.id,
      import.id,
      row_key,
      external_key,
      source_position,
      values,
      actor: context.manager
    )
  end

  defp published_schema(organization_id, dataset_id, manager) do
    schema = Datasets.create_schema_version!(organization_id, dataset_id, actor: manager)

    root =
      Datasets.add_record_type!(organization_id, schema.id, "customer", "Customer",
        actor: manager
      )

    for {key, family, required} <- [
          {"name", "text", true},
          {"balance", "decimal", false},
          {"joined_at", "utc_datetime", false}
        ] do
      Datasets.add_field_definition!(
        organization_id,
        root.id,
        key,
        key,
        family,
        "single",
        required,
        actor: manager
      )
    end

    Datasets.publish_schema_version!(organization_id, schema.id, root.id, actor: manager)
  end
end
