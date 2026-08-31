defmodule QuickTrain.Datasets.DatasetSchemaLifecycleTest do
  use QuickTrain.DataCase, async: true

  alias QuickTrain.{Accounts, AshError, Datasets}

  setup do
    manager = Accounts.register_user!("dataset-manager@example.test", "Dataset Manager")
    graph = Accounts.bootstrap_first_manager!(manager.id, "dataset-org", "Dataset Org")
    Datasets.grant_product_capabilities!(graph.organization.id, manager.id)

    %{manager: manager, organization: graph.organization}
  end

  test "creates, validates, publishes, and versions an organization dataset schema", context do
    %{manager: manager, organization: organization} = context

    dataset =
      Datasets.create_dataset!(organization.id, "customers", "Customers", actor: manager)

    schema = Datasets.create_schema_version!(organization.id, dataset.id, actor: manager)
    assert schema.version == 1
    assert schema.state == "draft"

    root =
      Datasets.add_record_type!(
        organization.id,
        schema.id,
        "customer",
        "Customer",
        actor: manager
      )

    fields =
      Enum.map(
        [
          {"name", "Name", "text", true},
          {"age", "Age", "integer", false},
          {"balance", "Balance", "decimal", false},
          {"active", "Active", "boolean", true},
          {"joined_at", "Joined At", "utc_datetime", false},
          {"avatar", "Avatar", "asset", false}
        ],
        fn {key, name, family, required} ->
          field =
            Datasets.add_field_definition!(
              organization.id,
              root.id,
              key,
              name,
              family,
              "single",
              required,
              actor: manager
            )

          assert field.value_family == family
          assert field.cardinality == "single"
          assert field.required == required
          field
        end
      )

    assert {:error, duplicate_error} =
             Datasets.add_field_definition(
               organization.id,
               root.id,
               "name",
               "Duplicate Name",
               "text",
               "single",
               false,
               actor: manager
             )

    assert Exception.message(duplicate_error) =~ "already been taken"

    assert {:error, family_error} =
             Datasets.add_field_definition(
               organization.id,
               root.id,
               "unsupported",
               "Unsupported",
               "json",
               "single",
               false,
               actor: manager
             )

    assert Exception.message(family_error) =~ "invalid_value_family"

    assert {:error, cardinality_error} =
             Datasets.add_field_definition(
               organization.id,
               root.id,
               "tags",
               "Tags",
               "text",
               "many",
               false,
               actor: manager
             )

    assert Exception.message(cardinality_error) =~ "invalid_cardinality"

    published =
      Datasets.publish_schema_version!(organization.id, schema.id, root.id, actor: manager)

    assert published.state == "published"
    assert published.root_record_type_id == root.id
    assert %DateTime{} = published.published_at

    assert_schema_immutable(organization.id, schema.id, root.id, hd(fields).id, manager)

    next_schema = Datasets.create_schema_version!(organization.id, dataset.id, actor: manager)
    assert next_schema.version == 2
    assert next_schema.state == "draft"
  end

  test "draft record types and fields can be edited and deleted", context do
    %{manager: manager, organization: organization} = context
    {schema, root} = create_draft_schema(organization.id, manager)

    updated_root =
      Datasets.update_record_type!(
        organization.id,
        root.id,
        "person",
        "Person",
        actor: manager
      )

    assert updated_root.key == "person"

    field =
      Datasets.add_field_definition!(
        organization.id,
        root.id,
        "name",
        "Name",
        "text",
        "single",
        true,
        actor: manager
      )

    updated_field =
      Datasets.update_field_definition!(
        organization.id,
        field.id,
        "display_name",
        "Display Name",
        "text",
        "single",
        false,
        actor: manager
      )

    assert updated_field.key == "display_name"
    refute updated_field.required

    assert :ok = Datasets.remove_field_definition!(organization.id, field.id, actor: manager)

    removable =
      Datasets.add_record_type!(
        organization.id,
        schema.id,
        "removable",
        "Removable",
        actor: manager
      )

    assert :ok = Datasets.remove_record_type!(organization.id, removable.id, actor: manager)
  end

  test "publication rejects a root record type from another schema", context do
    %{manager: manager, organization: organization} = context
    {first_schema, _first_root} = create_draft_schema(organization.id, manager, "first")
    {_second_schema, second_root} = create_draft_schema(organization.id, manager, "second")

    assert {:error, error} =
             Datasets.publish_schema_version(
               organization.id,
               first_schema.id,
               second_root.id,
               actor: manager
             )

    assert Exception.message(error) =~ "invalid_schema"

    assert Ash.get!(QuickTrain.Datasets.DatasetSchemaVersion, first_schema.id, authorize?: false).state ==
             "draft"
  end

  test "database constraints backstop publication facts and same-schema root ownership",
       context do
    %{manager: manager, organization: organization} = context
    {first_schema, _first_root} = create_draft_schema(organization.id, manager, "db-first")
    {_second_schema, second_root} = create_draft_schema(organization.id, manager, "db-second")

    assert {:error, cross_schema_error} =
             first_schema
             |> Ash.Changeset.for_update(:publish_internal, %{
               root_record_type_id: second_root.id,
               published_at: DateTime.utc_now()
             })
             |> Ash.update(authorize?: false)

    assert AshError.constraint?(cross_schema_error, [
             "dataset_schema_versions_root_record_type_id_schema_id_fkey"
           ])

    assert {:error, publication_facts_error} =
             first_schema
             |> Ash.Changeset.for_update(:publish_internal, %{
               root_record_type_id: nil,
               published_at: DateTime.utc_now()
             })
             |> Ash.update(authorize?: false)

    assert AshError.constraint?(publication_facts_error, [
             "dataset_schema_versions_publication_facts_valid"
           ])
  end

  test "an edit that waits behind publication rechecks the parent and fails", context do
    %{manager: manager, organization: organization} = context
    {schema, root} = create_draft_schema(organization.id, manager, "race")
    parent = self()
    handler_id = "dataset-publication-race-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        [:quick_train, :repo, :query],
        fn _event, _measurements, metadata, test_pid ->
          if Process.get(:pause_after_schema_lock) == true and
               String.contains?(metadata.query, ~s(FROM "dataset_schema_versions")) and
               String.contains?(metadata.query, "FOR UPDATE") do
            send(test_pid, {:publication_locked, self()})

            receive do
              :commit_publication -> :ok
            after
              5_000 -> raise "publication race test timed out"
            end
          end
        end,
        parent
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    publisher =
      Task.async(fn ->
        receive do
          :start -> :ok
        end

        Process.put(:pause_after_schema_lock, true)

        Datasets.publish_schema_version(
          organization.id,
          schema.id,
          root.id,
          actor: manager
        )
      end)

    Ecto.Adapters.SQL.Sandbox.allow(QuickTrain.Repo, self(), publisher.pid)
    send(publisher.pid, :start)
    assert_receive {:publication_locked, publisher_pid}, 5_000
    assert publisher_pid == publisher.pid

    editor =
      Task.async(fn ->
        receive do
          :start -> :ok
        end

        Datasets.update_record_type(
          organization.id,
          root.id,
          "too_late",
          "Too Late",
          actor: manager
        )
      end)

    Ecto.Adapters.SQL.Sandbox.allow(QuickTrain.Repo, self(), editor.pid)
    send(editor.pid, :start)
    assert Task.yield(editor, 100) == nil

    send(publisher.pid, :commit_publication)
    assert {:ok, {:ok, published}} = Task.yield(publisher, 5_000)
    assert published.state == "published"

    assert {:ok, {:error, edit_error}} = Task.yield(editor, 5_000)
    assert Exception.message(edit_error) =~ "schema_not_draft"

    unchanged = Ash.get!(QuickTrain.Datasets.DatasetRecordType, root.id, authorize?: false)
    assert unchanged.key == "customer"
  end

  test "dataset actions deny missing capability and cross-organization scope", context do
    %{manager: manager, organization: organization} = context
    outsider = Accounts.register_user!("dataset-outsider@example.test", "Dataset Outsider")

    assert {:error, error} =
             Datasets.create_dataset(
               organization.id,
               "forbidden",
               "Forbidden",
               actor: outsider
             )

    assert Exception.message(error) =~ "forbidden"

    {schema, _root} = create_draft_schema(organization.id, manager)

    other =
      Accounts.bootstrap_first_manager!(outsider.id, "other-dataset-org", "Other Dataset Org")

    Datasets.grant_product_capabilities!(other.organization.id, outsider.id)

    assert {:error, scoped_error} =
             Datasets.add_record_type(
               other.organization.id,
               schema.id,
               "intruder",
               "Intruder",
               actor: outsider
             )

    assert Exception.message(scoped_error) =~ "invalid_schema"

    assert {:error, read_error} =
             Datasets.get_schema_version(other.organization.id, schema.id, actor: outsider)

    assert Exception.message(read_error) =~ "not found"

    inactive_organization =
      organization
      |> Ash.Changeset.for_update(:update, %{status: "inactive"}, authorize?: false)
      |> Ash.update!()

    assert inactive_organization.status == "inactive"

    assert {:error, inactive_error} =
             Datasets.list_datasets(organization.id, actor: manager)

    assert Exception.message(inactive_error) =~ "forbidden"
  end

  defp create_draft_schema(organization_id, manager, suffix \\ "primary") do
    dataset =
      Datasets.create_dataset!(
        organization_id,
        "customers-#{suffix}",
        "Customers #{suffix}",
        actor: manager
      )

    schema = Datasets.create_schema_version!(organization_id, dataset.id, actor: manager)

    root =
      Datasets.add_record_type!(
        organization_id,
        schema.id,
        "customer",
        "Customer",
        actor: manager
      )

    {schema, root}
  end

  defp assert_schema_immutable(
         organization_id,
         schema_id,
         root_id,
         field_definition_id,
         manager
       ) do
    operations = [
      fn ->
        Datasets.add_record_type(
          organization_id,
          schema_id,
          "late",
          "Late",
          actor: manager
        )
      end,
      fn ->
        Datasets.update_record_type(
          organization_id,
          root_id,
          "changed",
          "Changed",
          actor: manager
        )
      end,
      fn -> Datasets.remove_record_type(organization_id, root_id, actor: manager) end,
      fn ->
        Datasets.add_field_definition(
          organization_id,
          root_id,
          "late",
          "Late",
          "text",
          "single",
          false,
          actor: manager
        )
      end,
      fn ->
        Datasets.update_field_definition(
          organization_id,
          field_definition_id,
          "changed",
          "Changed",
          "text",
          "single",
          false,
          actor: manager
        )
      end,
      fn ->
        Datasets.remove_field_definition(
          organization_id,
          field_definition_id,
          actor: manager
        )
      end
    ]

    Enum.each(operations, fn operation ->
      assert {:error, error} = operation.()
      assert Exception.message(error) =~ "schema_not_draft"
    end)
  end
end
