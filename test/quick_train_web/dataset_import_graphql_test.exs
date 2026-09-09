defmodule QuickTrainWeb.DatasetImportGraphqlTest do
  use QuickTrain.ConnCase, async: false
  use Oban.Testing, repo: QuickTrain.Repo

  alias QuickTrain.{Accounts, Datasets}
  alias QuickTrain.Datasets.Workers.ProcessImportRow

  setup %{conn: conn} do
    manager = Accounts.register_user!("graphql-imports@example.test", "GraphQL Imports")
    graph = Accounts.bootstrap_first_manager!(manager.id, "graphql-imports", "GraphQL Imports")
    Datasets.grant_dataset_and_asset_capabilities!(graph.organization.id, manager.id)
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

  test "transactional import failures have stable GraphQL codes", context do
    response =
      context.conn
      |> post("/graphql", %{
        query: """
        mutation {
          openDatasetImport(organizationId: "#{context.organization.id}",
            datasetId: "#{context.dataset.id}", schemaVersionId: "#{Ash.UUID.generate()}",
            idempotencyKey: "invalid-schema") { id }
        }
        """
      })
      |> json_response(200)

    assert [%{"code" => "invalid_schema", "message" => "invalid_schema"}] = response["errors"]
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

    finalized =
      graphql!(
        context.conn,
        """
        mutation Finalize($organizationId: ID!, $importId: ID!) {
          finalizeDatasetImport(organizationId: $organizationId, importId: $importId) {
            id phase
          }
        }
        """,
        %{"organizationId" => context.organization.id, "importId" => opened["id"]}
      )["finalizeDatasetImport"]

    assert finalized["phase"] == "SEALED"

    assert [%Oban.Job{args: %{"row_id" => row_id}}] =
             all_enqueued(worker: ProcessImportRow)

    assert :ok = perform_job(ProcessImportRow, %{"row_id" => row_id})

    data =
      graphql!(
        context.conn,
        """
        query Inspect($organizationId: ID!, $importId: ID!) {
          datasetImport(organizationId: $organizationId, importId: $importId) {
            importId phase lifecycle rowCount pending succeeded unchanged failed
            dataset { id key }
            schemaVersion { id version }
            rows(first: 1) {
              edges {
                cursor
                node {
                  id rowKey outcome
                  itemRevision { id revisionNumber }
                }
              }
              pageInfo { hasNextPage endCursor }
            }
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
    assert data["datasetImport"]["lifecycle"] == "PARTIALLY_FAILED"
    assert data["datasetImport"]["dataset"]["id"] == context.dataset.id
    assert data["datasetImport"]["schemaVersion"]["id"] == context.schema.id

    assert [%{"cursor" => nested_cursor, "node" => nested_row}] =
             data["datasetImport"]["rows"]["edges"]

    assert is_binary(nested_cursor)
    assert nested_row["rowKey"] == "valid"
    assert nested_row["outcome"] == "SUCCEEDED"
    assert is_binary(nested_row["itemRevision"]["id"])
    assert nested_row["itemRevision"]["revisionNumber"] == 1
    assert data["datasetImport"]["rows"]["pageInfo"]["hasNextPage"]
    assert is_binary(data["datasetImport"]["rows"]["pageInfo"]["endCursor"])

    assert [%{"cursor" => cursor, "node" => %{"rowKey" => "valid"}}] =
             data["datasetImportRows"]["edges"]

    assert is_binary(cursor)
    assert data["datasetImportRows"]["pageInfo"]["hasNextPage"]
    assert is_binary(data["datasetImportRows"]["pageInfo"]["endCursor"])
  end
end
