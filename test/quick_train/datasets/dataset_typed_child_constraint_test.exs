defmodule QuickTrain.Datasets.DatasetTypedChildConstraintTest do
  use QuickTrain.DataCase, async: false

  alias QuickTrain.{Accounts, Datasets}

  setup do
    manager = Accounts.register_user!("typed-constraint@example.test", "Typed Constraint")
    graph = Accounts.bootstrap_first_manager!(manager.id, "typed-constraint", "Typed Constraint")
    Datasets.grant_dataset_and_asset_capabilities!(graph.organization.id, manager.id)

    dataset =
      Datasets.create_dataset!(graph.organization.id, "records", "Records", actor: manager)

    schema = Datasets.create_schema_version!(graph.organization.id, dataset.id, actor: manager)

    root =
      Datasets.add_record_type!(
        graph.organization.id,
        schema.id,
        "record",
        "Record",
        actor: manager
      )

    text_field =
      Datasets.add_field_definition!(
        graph.organization.id,
        root.id,
        "name",
        "Name",
        "text",
        "single",
        false,
        actor: manager
      )

    integer_field =
      Datasets.add_field_definition!(
        graph.organization.id,
        root.id,
        "count",
        "Count",
        "integer",
        "single",
        false,
        actor: manager
      )

    Datasets.publish_schema_version!(graph.organization.id, schema.id, root.id, actor: manager)

    record_id = Ecto.UUID.generate()

    Repo.query!(
      """
      INSERT INTO dataset_records
        (id, organization_id, dataset_id, schema_version_id, record_type_id)
      VALUES ($1::text::uuid, $2::text::uuid, $3::text::uuid, $4::text::uuid, $5::text::uuid)
      """,
      [record_id, graph.organization.id, dataset.id, schema.id, root.id]
    )

    %{
      organization_id: graph.organization.id,
      dataset_id: dataset.id,
      schema_version_id: schema.id,
      record_type_id: root.id,
      record_id: record_id,
      text_field: text_field,
      integer_field: integer_field
    }
  end

  test "rejects an occurrence with no typed child", context do
    insert_occurrence(context, context.text_field.id)
    assert_typed_child_constraint!()
  end

  test "rejects a typed child whose table does not match the field family", context do
    value_id = insert_occurrence(context, context.text_field.id)

    Repo.query!(
      "INSERT INTO dataset_integer_values (dataset_value_id, value) VALUES ($1::text::uuid, $2)",
      [value_id, 42]
    )

    assert_typed_child_constraint!()
  end

  test "rejects more than one typed child for one occurrence", context do
    value_id = insert_occurrence(context, context.text_field.id)

    Repo.query!(
      "INSERT INTO dataset_text_values (dataset_value_id, value) VALUES ($1::text::uuid, $2)",
      [value_id, "valid"]
    )

    Repo.query!(
      "INSERT INTO dataset_integer_values (dataset_value_id, value) VALUES ($1::text::uuid, $2)",
      [value_id, 42]
    )

    assert_typed_child_constraint!()
  end

  test "accepts exactly one compatible typed child", context do
    value_id = insert_occurrence(context, context.integer_field.id)

    Repo.query!(
      "INSERT INTO dataset_integer_values (dataset_value_id, value) VALUES ($1::text::uuid, $2)",
      [value_id, 42]
    )

    assert %{num_rows: 0} = Repo.query!("SET CONSTRAINTS ALL IMMEDIATE")
  end

  defp insert_occurrence(context, field_definition_id) do
    value_id = Ecto.UUID.generate()

    Repo.query!(
      """
      INSERT INTO dataset_values
        (id, organization_id, dataset_id, schema_version_id, record_type_id,
         record_id, field_definition_id, ordinal)
      VALUES (
        $1::text::uuid, $2::text::uuid, $3::text::uuid, $4::text::uuid,
        $5::text::uuid, $6::text::uuid, $7::text::uuid, 0
      )
      """,
      [
        value_id,
        context.organization_id,
        context.dataset_id,
        context.schema_version_id,
        context.record_type_id,
        context.record_id,
        field_definition_id
      ]
    )

    value_id
  end

  defp assert_typed_child_constraint! do
    error = assert_raise Postgrex.Error, fn -> Repo.query!("SET CONSTRAINTS ALL IMMEDIATE") end
    assert error.postgres.constraint == "dataset_values_exactly_one_typed_child"
  end
end
