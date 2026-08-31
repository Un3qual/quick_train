defmodule QuickTrainWeb.DatasetImportGraphqlTest do
  use QuickTrain.ConnCase, async: false

  alias QuickTrain.{Accounts, Datasets}

  setup %{conn: conn} do
    manager = Accounts.register_user!("graphql-imports@example.test", "GraphQL Imports")
    graph = Accounts.bootstrap_first_manager!(manager.id, "graphql-imports", "GraphQL Imports")
    Datasets.grant_product_capabilities!(graph.organization.id, manager.id)
    session = Accounts.issue_bearer_session!(manager.id)

    dataset =
      Datasets.create_dataset!(graph.organization.id, "customers", "Customers", actor: manager)

    schema = Datasets.create_schema_version!(graph.organization.id, dataset.id, actor: manager)

    root =
      Datasets.add_record_type!(graph.organization.id, schema.id, "customer", "Customer",
        actor: manager
      )

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

    %{
      conn: put_req_header(conn, "authorization", "Bearer #{session.token}"),
      organization: graph.organization,
      dataset: dataset,
      schema: schema
    }
  end

  test "GraphQL import lifecycle uses fixed flat input and a keyset Relay row connection",
       context do
    opened =
      graphql!(
        context.conn,
        """
        mutation Open($organizationId: ID!, $datasetId: ID!, $schemaVersionId: ID!) {
          openDatasetImport(
            organizationId: $organizationId,
            datasetId: $datasetId,
            schemaVersionId: $schemaVersionId,
            idempotencyKey: "graphql-batch"
          ) { id phase schemaVersionId }
        }
        """,
        %{
          "organizationId" => context.organization.id,
          "datasetId" => context.dataset.id,
          "schemaVersionId" => context.schema.id
        }
      )["openDatasetImport"]

    assert opened["phase"] == "OPEN"

    for {row_key, source_position, values, expected_outcome} <- [
          {"valid", 0, [%{"field" => "name", "text" => "Alice"}], "PENDING"},
          {"invalid", 1, [], "FAILED"}
        ] do
      row =
        graphql!(
          context.conn,
          """
          mutation Append(
            $organizationId: ID!,
            $importId: ID!,
            $rowKey: String!,
            $sourcePosition: Int!,
            $values: [DatasetImportRowValuesInput!]!
          ) {
            appendDatasetImportRow(
              organizationId: $organizationId,
              importId: $importId,
              rowKey: $rowKey,
              sourcePosition: $sourcePosition,
              values: $values
            ) { id rowKey sourcePosition outcome errorCode }
          }
          """,
          %{
            "organizationId" => context.organization.id,
            "importId" => opened["id"],
            "rowKey" => row_key,
            "sourcePosition" => source_position,
            "values" => values
          }
        )["appendDatasetImportRow"]

      assert row["rowKey"] == row_key
      assert row["outcome"] == expected_outcome
    end

    data =
      graphql!(
        context.conn,
        """
        query Inspect($organizationId: ID!, $importId: ID!) {
          datasetImport(organizationId: $organizationId, importId: $importId) {
            importId phase lifecycle rowCount pending succeeded unchanged failed
          }
          datasetImportRows(
            organizationId: $organizationId,
            importId: $importId,
            first: 1
          ) {
            edges { cursor node { id rowKey sourcePosition outcome errorCode itemRevisionId } }
            pageInfo { hasNextPage endCursor }
          }
        }
        """,
        %{"organizationId" => context.organization.id, "importId" => opened["id"]}
      )

    assert data["datasetImport"]["rowCount"] == 2
    assert data["datasetImport"]["lifecycle"] == "OPEN"

    assert [%{"cursor" => cursor, "node" => %{"rowKey" => "valid"}}] =
             data["datasetImportRows"]["edges"]

    assert is_binary(cursor)
    assert data["datasetImportRows"]["pageInfo"]["hasNextPage"]
    assert is_binary(data["datasetImportRows"]["pageInfo"]["endCursor"])
  end

  defp graphql!(conn, query, variables) do
    response =
      conn |> post("/graphql", %{query: query, variables: variables}) |> json_response(200)

    assert is_nil(response["errors"]), inspect(response["errors"])
    response["data"]
  end
end
