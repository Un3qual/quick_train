defmodule QuickTrainWeb.DatasetRevisionGraphqlTest do
  use QuickTrain.ConnCase, async: false

  alias QuickTrain.{Accounts, Datasets}

  setup %{conn: conn} do
    manager = Accounts.register_user!("graphql-revisions@example.test", "GraphQL Revisions")

    graph =
      Accounts.bootstrap_first_manager!(manager.id, "graphql-revisions", "GraphQL Revisions")

    Datasets.grant_product_capabilities!(graph.organization.id, manager.id)
    session = Accounts.issue_bearer_session!(manager.id)

    dataset =
      Datasets.create_dataset!(graph.organization.id, "customers", "Customers", actor: manager)

    schema = Datasets.create_schema_version!(graph.organization.id, dataset.id, actor: manager)

    root =
      Datasets.add_record_type!(graph.organization.id, schema.id, "customer", "Customer",
        actor: manager
      )

    field =
      Datasets.add_field_definition!(
        graph.organization.id,
        root.id,
        "name",
        "Name",
        "text",
        "single",
        true,
        actor: manager
      )

    schema =
      Datasets.publish_schema_version!(graph.organization.id, schema.id, root.id, actor: manager)

    result =
      Datasets.put_item_revision!(
        graph.organization.id,
        dataset.id,
        schema.id,
        nil,
        "customer-1",
        [%{field: "name", text: "Alice"}],
        actor: manager
      )

    %{
      conn: put_req_header(conn, "authorization", "Bearer #{session.token}"),
      organization: graph.organization,
      dataset: dataset,
      field: field,
      result: result
    }
  end

  test "typed item, revision, and value reads are keyset Relay connections", context do
    data =
      graphql!(
        context.conn,
        """
        query TypedRevision(
          $organizationId: ID!,
          $datasetId: ID!,
          $itemId: ID!,
          $revisionId: ID!
        ) {
          datasetItems(
            organizationId: $organizationId,
            datasetId: $datasetId,
            first: 1
          ) {
            edges { cursor node { id datasetId externalKey } }
            pageInfo { hasNextPage endCursor }
          }
          datasetItemRevisions(
            organizationId: $organizationId,
            itemId: $itemId,
            first: 1
          ) {
            edges {
              cursor
              node {
                id itemId schemaVersionId rootRecordTypeId rootRecordId revisionNumber fingerprint
              }
            }
            pageInfo { hasNextPage endCursor }
          }
          datasetValues(
            organizationId: $organizationId,
            revisionId: $revisionId,
            first: 1
          ) {
            edges {
              cursor
              node {
                id fieldDefinitionId ordinal
                textValue { value }
              }
            }
            pageInfo { hasNextPage endCursor }
          }
        }
        """,
        %{
          "organizationId" => context.organization.id,
          "datasetId" => context.dataset.id,
          "itemId" => context.result.item.id,
          "revisionId" => context.result.revision.id
        }
      )

    assert [%{"cursor" => item_cursor, "node" => item}] = data["datasetItems"]["edges"]
    assert is_binary(item_cursor)
    assert item["id"] == context.result.item.id
    assert item["externalKey"] == "customer-1"

    assert [%{"cursor" => revision_cursor, "node" => revision}] =
             data["datasetItemRevisions"]["edges"]

    assert is_binary(revision_cursor)
    assert revision["id"] == context.result.revision.id
    assert revision["revisionNumber"] == 1

    assert [%{"cursor" => value_cursor, "node" => value}] = data["datasetValues"]["edges"]
    assert is_binary(value_cursor)
    assert value["fieldDefinitionId"] == context.field.id
    assert value["ordinal"] == 0
    assert value["textValue"]["value"] == "Alice"

    for connection <- ~w(datasetItems datasetItemRevisions datasetValues) do
      refute data[connection]["pageInfo"]["hasNextPage"]
      assert is_binary(data[connection]["pageInfo"]["endCursor"])
    end
  end

  defp graphql!(conn, query, variables) do
    response =
      conn |> post("/graphql", %{query: query, variables: variables}) |> json_response(200)

    assert is_nil(response["errors"]), inspect(response["errors"])
    response["data"]
  end
end
