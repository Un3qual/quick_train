defmodule QuickTrain.Datasets.DatasetRevisionTest do
  use QuickTrain.DataCase, async: false

  alias QuickTrain.{Accounts, Assets, Datasets}
  alias QuickTrain.Assets.Storage.Test, as: TestStorage

  alias QuickTrain.Datasets.{
    DatasetItem,
    DatasetItemRevision,
    DatasetRecord,
    DatasetValue,
    Fingerprint
  }

  setup do
    :ok = TestStorage.reset()

    manager = Accounts.register_user!("revision-manager@example.test", "Revision Manager")
    graph = Accounts.bootstrap_first_manager!(manager.id, "revision-org", "Revision Org")
    Datasets.grant_product_capabilities!(graph.organization.id, manager.id)

    asset = ready_asset(graph.organization.id, manager, "avatar bytes")
    graph = published_schema(graph.organization.id, manager)

    Map.merge(graph, %{manager: manager, organization: graph.organization, asset: asset})
  end

  test "enum-backed value families preserve version one fingerprint identities" do
    schema_id = "11111111-1111-1111-1111-111111111111"
    root_id = "22222222-2222-2222-2222-222222222222"
    field = %{id: "33333333-3333-3333-3333-333333333333"}

    revision_fingerprint =
      Fingerprint.revision(schema_id, root_id, [
        %{field: field, family: :text, ordinal: 0, value: "Alice"}
      ])

    import_fingerprint =
      Fingerprint.import_row(schema_id, "row-1", "customer-1", 7, [
        %{field: "name", family: :text, value: "Alice"}
      ])

    assert revision_fingerprint ==
             "aabd266a1733aaa09d2bcfd2f77c880fc4f749acf81d1a020a4363ce23cf59ad"

    assert import_fingerprint ==
             "4dd8e574b1b5092f01bd98d8043ab31eb2756306c641573390ddba19eb275518"
  end

  test "constructs all six typed values and preserves immutable historical revisions", context do
    first_values = values(context.asset.id, "Alice", "1.00", "2026-01-02T03:04:05.123456+02:00")

    first =
      Datasets.put_item_revision!(
        context.organization.id,
        context.dataset.id,
        context.schema.id,
        nil,
        "customer-1",
        first_values,
        actor: context.manager
      )

    assert first.changed
    assert first.item.external_key == "customer-1"
    assert first.revision.revision_number == 1
    assert first.revision.schema_version_id == context.schema.id
    assert first.revision.root_record_type_id == context.root.id
    assert Regex.match?(~r/\A[0-9a-f]{64}\z/, first.revision.fingerprint)

    loaded_first = load_revision(first.revision)
    assert [_, _, _, _, _, _] = loaded_first.root_record.values

    assert typed_values(loaded_first) == %{
             "active" => true,
             "age" => 42,
             "avatar" => context.asset.id,
             "balance" => Decimal.new("1.00"),
             "joined_at" => ~U[2026-01-02 01:04:05.123456Z],
             "name" => "Alice"
           }

    equivalent =
      first_values
      |> Enum.reverse()
      |> Enum.map(fn
        %{field: "balance"} = entry -> %{entry | decimal: "1.0"}
        %{field: "joined_at"} = entry -> %{entry | utc_datetime: "2026-01-02T01:04:05.123456Z"}
        entry -> entry
      end)

    unchanged =
      Datasets.put_item_revision!(
        context.organization.id,
        context.dataset.id,
        context.schema.id,
        nil,
        "customer-1",
        equivalent,
        actor: context.manager
      )

    refute unchanged.changed
    assert unchanged.item.id == first.item.id
    assert unchanged.revision.id == first.revision.id
    assert Ash.count!(DatasetItemRevision, authorize?: false) == 1

    changed_values = values(context.asset.id, "Alice Updated", "1", "2026-01-02T01:04:05.123456Z")

    second =
      Datasets.put_item_revision!(
        context.organization.id,
        context.dataset.id,
        context.schema.id,
        nil,
        "customer-1",
        changed_values,
        actor: context.manager
      )

    assert second.changed
    assert second.item.id == first.item.id
    assert second.revision.revision_number == 2
    refute second.revision.fingerprint == first.revision.fingerprint

    historical = load_revision(first.revision)
    assert typed_values(historical)["name"] == "Alice"
    assert Ash.count!(DatasetRecord, authorize?: false) == 2
    assert Ash.count!(DatasetItemRevision, authorize?: false) == 2

    page =
      Datasets.list_item_revisions!(context.organization.id, first.item.id,
        page: [limit: 1],
        actor: context.manager
      )

    assert %Ash.Page.Keyset{results: [latest], more?: true} = page
    assert latest.id == second.revision.id

    assert %Ash.Page.Keyset{results: [older], more?: false} = Ash.page!(page, :next)
    assert older.id == first.revision.id

    value_page =
      Datasets.list_values!(context.organization.id, first.revision.id,
        page: [limit: 1],
        actor: context.manager
      )

    assert %Ash.Page.Keyset{results: [_value], more?: true} = value_page
  end

  test "the same values under a new schema create a distinct revision", context do
    first = put!(context, values(context.asset.id, "Alice", "1", "2026-01-02T01:04:05Z"))
    next_schema = cloned_published_schema(context, context.manager)

    second =
      Datasets.put_item_revision!(
        context.organization.id,
        context.dataset.id,
        next_schema.schema.id,
        nil,
        "customer-1",
        values(context.asset.id, "Alice", "1.0", "2026-01-02T01:04:05+00:00"),
        actor: context.manager
      )

    assert first.item.id == second.item.id
    assert second.changed
    assert second.revision.revision_number == 2
    refute first.revision.fingerprint == second.revision.fingerprint
  end

  test "negative decimal zero canonicalizes to zero", context do
    first =
      put!(
        context,
        values(context.asset.id, "Zero", "-0.000", "2026-01-02T01:04:05Z")
      )

    second =
      put!(context, values(context.asset.id, "Zero", "0", "2026-01-02T01:04:05Z"))

    refute second.changed
    assert second.revision.id == first.revision.id
  end

  @tag :committed_db
  test "concurrent first writes converge on one stable item and revision", context do
    input = values(context.asset.id, "Concurrent", "1", "2026-01-02T01:04:05Z")

    results =
      concurrently(
        for _index <- 1..2 do
          fn ->
            Datasets.put_item_revision(
              context.organization.id,
              context.dataset.id,
              context.schema.id,
              nil,
              "concurrent-customer",
              input,
              actor: context.manager
            )
          end
        end
      )

    assert Enum.all?(results, &match?({:ok, %{}}, &1))

    revision_results = Enum.map(results, fn {:ok, result} -> result end)
    assert Enum.count(revision_results, & &1.changed) == 1
    assert revision_results |> Enum.map(& &1.item.id) |> Enum.uniq() |> length() == 1
    assert revision_results |> Enum.map(& &1.revision.id) |> Enum.uniq() |> length() == 1
    assert Ash.count!(DatasetItem, authorize?: false) == 1
    assert Ash.count!(DatasetItemRevision, authorize?: false) == 1
  end

  test "a supplied keyless identity remains stable", context do
    item_id = Ecto.UUID.generate()
    input = values(context.asset.id, "Keyless", "2", "2026-01-02T01:04:05Z")

    first =
      Datasets.put_item_revision!(
        context.organization.id,
        context.dataset.id,
        context.schema.id,
        item_id,
        nil,
        input,
        actor: context.manager
      )

    second =
      Datasets.put_item_revision!(
        context.organization.id,
        context.dataset.id,
        context.schema.id,
        item_id,
        nil,
        input,
        actor: context.manager
      )

    assert first.item.id == item_id
    assert is_nil(first.item.external_key)
    refute second.changed
    assert second.revision.id == first.revision.id
  end

  test "rejects cross-dataset schemas and non-ready or cross-organization assets atomically",
       context do
    other_dataset =
      Datasets.create_dataset!(context.organization.id, "other", "Other", actor: context.manager)

    assert {:error, schema_error} =
             Datasets.put_item_revision(
               context.organization.id,
               other_dataset.id,
               context.schema.id,
               nil,
               "cross-schema",
               values(context.asset.id, "Alice", "1", "2026-01-02T01:04:05Z"),
               actor: context.manager
             )

    assert Exception.message(schema_error) =~ "invalid_schema"

    outsider = Accounts.register_user!("revision-outsider@example.test", "Revision Outsider")
    other = Accounts.bootstrap_first_manager!(outsider.id, "revision-other", "Revision Other")
    Datasets.grant_product_capabilities!(other.organization.id, outsider.id)
    foreign_asset = ready_asset(other.organization.id, outsider, "foreign avatar")

    assert {:error, asset_error} =
             Datasets.put_item_revision(
               context.organization.id,
               context.dataset.id,
               context.schema.id,
               nil,
               "cross-asset",
               values(foreign_asset.id, "Alice", "1", "2026-01-02T01:04:05Z"),
               actor: context.manager
             )

    assert Exception.message(asset_error) =~ "invalid_asset"

    assert {:error, forbidden_error} =
             Datasets.put_item_revision(
               context.organization.id,
               context.dataset.id,
               context.schema.id,
               nil,
               "unauthorized",
               values(context.asset.id, "Alice", "1", "2026-01-02T01:04:05Z"),
               actor: outsider
             )

    assert Exception.message(forbidden_error) =~ "forbidden"
    assert Ash.count!(DatasetItem, authorize?: false) == 0
    assert Ash.count!(DatasetItemRevision, authorize?: false) == 0
    assert Ash.count!(DatasetRecord, authorize?: false) == 0
  end

  test "rejects invalid flat records atomically", context do
    valid = values(context.asset.id, "Alice", "1", "2026-01-02T01:04:05Z")

    invalid_inputs = [
      {:required_missing, Enum.reject(valid, &(&1.field == "name"))},
      {:unknown_field, [%{field: "unknown", text: "value"} | valid]},
      {:type_mismatch,
       Enum.map(valid, fn
         %{field: "age"} -> %{field: "age", text: "42"}
         entry -> entry
       end)},
      {:repeated_single, [%{field: "name", text: "Again"} | valid]},
      {:unsupported_structure, [%{field: "name", record: %{name: "Nested"}} | tl(valid)]}
    ]

    Enum.each(invalid_inputs, fn {reason, input} ->
      assert {:error, error} =
               Datasets.put_item_revision(
                 context.organization.id,
                 context.dataset.id,
                 context.schema.id,
                 nil,
                 "invalid-#{reason}",
                 input,
                 actor: context.manager
               )

      assert Exception.message(error) =~ Atom.to_string(reason)
    end)

    assert Ash.count!(DatasetItem, authorize?: false) == 0
    assert Ash.count!(DatasetItemRevision, authorize?: false) == 0
    assert Ash.count!(DatasetRecord, authorize?: false) == 0
    assert Ash.count!(DatasetValue, authorize?: false) == 0
  end

  test "optional single fields may be omitted", context do
    input =
      context.asset.id
      |> values("Optional", "1", "2026-01-02T01:04:05Z")
      |> Enum.reject(&(&1.field == "balance"))

    result =
      Datasets.put_item_revision!(
        context.organization.id,
        context.dataset.id,
        context.schema.id,
        nil,
        "optional-customer",
        input,
        actor: context.manager
      )

    assert result.changed
    assert [_, _, _, _, _] = load_revision(result.revision).root_record.values
  end

  defp put!(context, values) do
    Datasets.put_item_revision!(
      context.organization.id,
      context.dataset.id,
      context.schema.id,
      nil,
      "customer-1",
      values,
      actor: context.manager
    )
  end

  defp published_schema(organization_id, manager) do
    dataset = Datasets.create_dataset!(organization_id, "customers", "Customers", actor: manager)
    schema = Datasets.create_schema_version!(organization_id, dataset.id, actor: manager)

    root =
      Datasets.add_record_type!(organization_id, schema.id, "customer", "Customer",
        actor: manager
      )

    fields =
      [
        {"name", "Name", "text", true},
        {"age", "Age", "integer", true},
        {"balance", "Balance", "decimal", false},
        {"active", "Active", "boolean", true},
        {"joined_at", "Joined At", "utc_datetime", true},
        {"avatar", "Avatar", "asset", true}
      ]
      |> Map.new(fn {key, name, family, required} ->
        field =
          Datasets.add_field_definition!(
            organization_id,
            root.id,
            key,
            name,
            family,
            "single",
            required,
            actor: manager
          )

        {key, field}
      end)

    schema = Datasets.publish_schema_version!(organization_id, schema.id, root.id, actor: manager)

    %{
      organization: %{id: organization_id},
      dataset: dataset,
      schema: schema,
      root: root,
      fields: fields
    }
  end

  defp cloned_published_schema(context, manager) do
    schema =
      Datasets.create_schema_version!(context.organization.id, context.dataset.id, actor: manager)

    root =
      Datasets.add_record_type!(context.organization.id, schema.id, "customer", "Customer",
        actor: manager
      )

    Enum.each(context.fields, fn {key, field} ->
      Datasets.add_field_definition!(
        context.organization.id,
        root.id,
        key,
        field.name,
        field.value_family,
        "single",
        field.required,
        actor: manager
      )
    end)

    schema =
      Datasets.publish_schema_version!(context.organization.id, schema.id, root.id,
        actor: manager
      )

    %{schema: schema, root: root}
  end

  defp values(asset_id, name, decimal, date_time) do
    [
      %{field: "name", text: name},
      %{field: "age", integer: 42},
      %{field: "balance", decimal: decimal},
      %{field: "active", boolean: true},
      %{field: "joined_at", utc_datetime: date_time},
      %{field: "avatar", asset_id: asset_id}
    ]
  end

  defp ready_asset(organization_id, manager, content) do
    registration =
      Assets.register_asset!(
        organization_id,
        Base.encode16(:crypto.hash(:sha256, content), case: :lower),
        byte_size(content),
        "text/plain",
        actor: manager
      )

    :ok = TestStorage.put_staging(registration.upload_access, content)
    Assets.finalize_asset!(registration.asset.id, organization_id, actor: manager).asset
  end

  defp load_revision(revision) do
    Ash.load!(
      revision,
      [
        root_record: [
          values: [
            :field_definition,
            :text_value,
            :integer_value,
            :decimal_value,
            :boolean_value,
            :date_time_value,
            :asset_value
          ]
        ]
      ],
      authorize?: false
    )
  end

  defp typed_values(revision) do
    Map.new(revision.root_record.values, fn value ->
      typed =
        case value.field_definition.value_family do
          :text -> value.text_value.value
          :integer -> value.integer_value.value
          :decimal -> value.decimal_value.value
          :boolean -> value.boolean_value.value
          :utc_datetime -> value.date_time_value.value
          :asset -> value.asset_value.asset_id
        end

      {value.field_definition.key, typed}
    end)
  end
end
