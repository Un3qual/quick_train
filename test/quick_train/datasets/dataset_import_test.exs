defmodule QuickTrain.Datasets.DatasetImportTest do
  use QuickTrain.DataCase, async: false
  use Oban.Testing, repo: QuickTrain.Repo

  require Ash.Query

  alias QuickTrain.{Accounts, Datasets}
  alias QuickTrain.Datasets.{DatasetImport, DatasetImportRow, DatasetItem, DatasetRecord}

  alias QuickTrain.Datasets.Workers.ProcessImportRow

  defmodule FailingScheduler do
    def enqueue_batch!(rows) do
      ProcessImportRow.enqueue_batch!(rows)
      raise "simulated_schedule_failure"
    end
  end

  setup do
    manager = Accounts.register_user!("import-manager@example.test", "Import Manager")
    graph = organization_manager_fixture(manager.id, "import-org", "Import Org")

    dataset =
      Datasets.create_dataset!(graph.organization.id, "customers", "Customers", actor: manager)

    schema = published_schema(graph.organization.id, dataset.id, manager)

    %{manager: manager, organization: graph.organization, dataset: dataset, schema: schema}
  end

  test "NUL identifiers fail before constructing a candidate", context do
    import = open!(context, "nul-identifiers")

    for {row_key, external_key, reason} <- [
          {"row" <> <<0>>, nil, "invalid_row_key"},
          {"row", "customer" <> <<0>>, "invalid_external_key"}
        ] do
      assert {:error, error} =
               Datasets.append_import_row(
                 context.organization.id,
                 import.id,
                 row_key,
                 external_key,
                 0,
                 [%{field: "name", text: "Alice"}],
                 actor: context.manager
               )

      assert Exception.message(error) =~ reason
      assert Ash.count!(DatasetImportRow, authorize?: false) == 0
      assert Ash.count!(DatasetRecord, authorize?: false) == 0
    end

    assert append!(context, import, "row", "customer", 0, [%{field: "name", text: "Alice"}]).outcome ==
             :pending
  end

  test "NUL text is rejected before reserving an import row", context do
    import = open!(context, "nul-text")

    assert {:error, error} =
             Datasets.append_import_row(
               context.organization.id,
               import.id,
               "row",
               nil,
               0,
               [%{field: "name", text: "bad" <> <<0>>}],
               actor: context.manager
             )

    assert Exception.message(error) =~ "malformed_text"
    assert Ash.count!(DatasetImportRow, authorize?: false) == 0
    assert Ash.count!(DatasetRecord, authorize?: false) == 0

    assert append!(context, import, "row", nil, 0, [%{field: "name", text: "valid"}]).outcome ==
             :pending
  end

  test "import text preserves whitespace and empty strings in content and identity", context do
    import = open!(context, "exact-text")

    for {text, position} <- Enum.with_index(["  Alice\n", "", " \n "]) do
      row_key = "row-#{position}"
      row = append!(context, import, row_key, nil, position, [%{field: "name", text: text}])
      assert row.outcome == :pending

      record = Ash.get!(DatasetRecord, row.candidate_record_id, authorize?: false)
      record = Ash.load!(record, [values: :text_value], authorize?: false)
      assert [%{text_value: %{value: ^text}}] = record.values

      assert append!(context, import, row_key, nil, position, [%{field: "name", text: text}]).id ==
               row.id

      assert {:error, error} =
               Datasets.append_import_row(
                 context.organization.id,
                 import.id,
                 row_key,
                 nil,
                 position,
                 [%{field: "name", text: text <> " "}],
                 actor: context.manager
               )

      assert Exception.message(error) =~ "idempotency_conflict"
    end
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

    sealed = Datasets.finalize_import!(context.organization.id, first.id, actor: context.manager)
    retry = open!(context, "batch-1")

    for field <- [:id, :phase, :sealed_at, :updated_at, :open_expires_at, :open_fingerprint] do
      assert Map.fetch!(retry, field) == Map.fetch!(sealed, field)
    end
  end

  @tag :committed_db
  test "concurrent opens converge and conflicting schemas retain one winner", context do
    [first, retry] =
      concurrently([fn -> open!(context, "same") end, fn -> open!(context, "same") end])

    assert first.id == retry.id
    assert first.open_expires_at == retry.open_expires_at

    next_schema = published_schema(context.organization.id, context.dataset.id, context.manager)

    results =
      concurrently(
        for schema <- [context.schema, next_schema] do
          fn ->
            Datasets.open_import(
              context.organization.id,
              context.dataset.id,
              schema.id,
              "conflict",
              actor: context.manager
            )
          end
        end
      )

    assert [{:ok, winner}] = Enum.filter(results, &match?({:ok, _}, &1))
    assert [{:error, error}] = Enum.filter(results, &match?({:error, _}, &1))
    assert Exception.message(error) =~ "idempotency_conflict"

    assert Ash.get!(DatasetImport, winner.id, authorize?: false).schema_version_id ==
             winner.schema_version_id

    assert Ash.count!(DatasetImport, authorize?: false) == 2
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

  test "source-position conflicts take precedence over another row's external key", context do
    import = open!(context, "conflict-precedence")
    values = [%{field: "name", text: "Alice"}]
    append!(context, import, "first", "first-customer", 0, values)
    append!(context, import, "second", "second-customer", 1, values)

    assert {:error, error} =
             Datasets.append_import_row(
               context.organization.id,
               import.id,
               "third",
               "first-customer",
               1,
               values,
               actor: context.manager
             )

    assert Exception.message(error) =~ "idempotency_conflict"
    assert Ash.count!(DatasetImportRow, authorize?: false) == 2
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

    assert {:ok, _outcome} = perform_job(ProcessImportRow, %{"row_id" => pending.id})
    completed = Ash.get!(DatasetImportRow, pending.id, authorize?: false)
    assert completed.outcome == :succeeded
    assert completed.item_revision_id

    revision =
      Ash.get!(QuickTrain.Datasets.DatasetItemRevision, completed.item_revision_id,
        authorize?: false
      )

    assert revision.root_record_id == pending.candidate_record_id
    assert Ash.count!(DatasetRecord, authorize?: false) == 1

    assert Ash.get!(DatasetRecord, revision.root_record_id, authorize?: false)

    assert {:ok, _outcome} = perform_job(ProcessImportRow, %{"row_id" => pending.id})
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

    assert {:ok, _outcome} = perform_job(ProcessImportRow, %{"row_id" => row.id})
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
        assert {:ok, _outcome} = perform_job(ProcessImportRow, %{"row_id" => row.id})
        Ash.get!(DatasetImportRow, row.id, authorize?: false)
      end

    assert first.outcome == :succeeded
    assert unchanged.outcome == :unchanged
    assert unchanged.item_revision_id == first.item_revision_id
    refute unchanged.candidate_record_id == first.candidate_record_id
    assert Ash.count!(DatasetRecord, authorize?: false) == 2
  end

  @tag :committed_db
  test "concurrent finalization enqueues every row once across multiple batches", context do
    import = open!(context, "concurrent-finalize")
    first = append!(context, import, "row-0", nil, 0, [%{field: "name", text: "Alice"}])

    attributes =
      Map.take(first, [
        :organization_id,
        :dataset_id,
        :import_id,
        :schema_version_id,
        :root_record_type_id,
        :candidate_record_id,
        :fingerprint,
        :outcome
      ])

    inputs =
      Enum.map(1..1000, fn n ->
        Map.merge(attributes, %{row_key: "row-#{n}", source_position: n})
      end)

    Ash.bulk_create!(inputs, DatasetImportRow, :create_internal,
      authorize?: false,
      return_errors?: true,
      transaction: :all
    )

    results =
      concurrently(
        for _n <- 1..2 do
          fn ->
            Datasets.finalize_import!(context.organization.id, import.id, actor: context.manager)
          end
        end
      )

    assert Enum.all?(results, &(&1.id == import.id and &1.phase == :sealed))
    jobs = all_enqueued(worker: ProcessImportRow)

    row_ids =
      DatasetImportRow
      |> Ash.Query.filter(import_id == ^import.id)
      |> Ash.read!(authorize?: false)
      |> Enum.map(& &1.id)

    assert Enum.sort(Enum.map(jobs, & &1.args["row_id"])) == Enum.sort(row_ids)
  end

  @tag :committed_db
  test "a row-job scheduling failure rolls sealing back atomically", context do
    import = open!(context, "schedule-rollback")
    append!(context, import, "row", "customer", 0, [%{field: "name", text: "Alice"}])

    Application.put_env(:quick_train, :dataset_import_row_scheduler, FailingScheduler)
    on_exit(fn -> Application.delete_env(:quick_train, :dataset_import_row_scheduler) end)

    error =
      assert_raise Ash.Error.Unknown, fn ->
        Datasets.finalize_import(context.organization.id, import.id, actor: context.manager)
      end

    assert Exception.message(error) =~ "simulated_schedule_failure"

    persisted = Ash.get!(DatasetImport, import.id, authorize?: false)
    assert persisted.phase == :open
    assert is_nil(persisted.sealed_at)
    assert all_enqueued(worker: ProcessImportRow) == []

    Application.delete_env(:quick_train, :dataset_import_row_scheduler)

    assert Datasets.finalize_import!(context.organization.id, import.id, actor: context.manager).phase ==
             :sealed

    assert [_job] = all_enqueued(worker: ProcessImportRow)
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
      assert {:ok, _outcome} = perform_job(ProcessImportRow, %{"row_id" => row.id})
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

  test "expired open imports reject append and finalization", context do
    import = open!(context, "expired")
    Ash.Seed.update!(import, %{open_expires_at: DateTime.add(DateTime.utc_now(), -1, :second)})

    assert {:error, append_error} =
             Datasets.append_import_row(
               context.organization.id,
               import.id,
               "late",
               nil,
               0,
               [%{field: "name", text: "Late"}],
               actor: context.manager
             )

    assert Exception.message(append_error) =~ "import_expired"

    assert {:error, finalize_error} =
             Datasets.finalize_import(
               context.organization.id,
               import.id,
               actor: context.manager
             )

    assert Exception.message(finalize_error) =~ "import_expired"
    assert Ash.get!(DatasetImport, import.id, authorize?: false).phase == :open
    assert Ash.count!(DatasetImportRow, authorize?: false) == 0
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
