defmodule QuickTrainWeb.DatasetSchemaGraphqlTest do
  use QuickTrain.ConnCase, async: false

  alias QuickTrain.{Accounts, Datasets}

  setup %{conn: conn} do
    manager = Accounts.register_user!("graphql-datasets@example.test", "GraphQL Datasets")
    graph = Accounts.bootstrap_first_manager!(manager.id, "graphql-datasets", "GraphQL Datasets")
    Datasets.grant_product_capabilities!(graph.organization.id, manager.id)
    session = Accounts.issue_bearer_session!(manager.id)

    %{conn: put_req_header(conn, "authorization", "Bearer #{session.token}"), graph: graph}
  end

  test "authenticated GraphQL exposes the deliberate typed schema lifecycle", %{
    conn: conn,
    graph: graph
  } do
    organization_id = graph.organization.id

    create_result =
      graphql!(
        conn,
        """
        mutation CreateDataset($input: CreateDatasetInput!) {
          createDataset(input: $input) {
            result { id organizationId key name }
            errors { message }
          }
        }
        """,
        %{
          "input" => %{
            "organizationId" => organization_id,
            "key" => "customers",
            "name" => "Customers"
          }
        }
      )["createDataset"]

    assert create_result["errors"] == []
    dataset = create_result["result"]
    assert dataset["organizationId"] == organization_id

    schema =
      graphql!(
        conn,
        """
        mutation CreateSchema($organizationId: ID!, $datasetId: ID!) {
          createDatasetSchemaVersion(
            organizationId: $organizationId,
            datasetId: $datasetId
          ) { id datasetId version state publishedAt rootRecordTypeId }
        }
        """,
        %{"organizationId" => organization_id, "datasetId" => dataset["id"]}
      )["createDatasetSchemaVersion"]

    assert schema["version"] == 1
    assert schema["state"] == "draft"

    root =
      graphql!(
        conn,
        """
        mutation AddRecordType(
          $organizationId: ID!,
          $schemaVersionId: ID!,
          $key: String!,
          $name: String!
        ) {
          addDatasetRecordType(
            organizationId: $organizationId,
            schemaVersionId: $schemaVersionId,
            key: $key,
            name: $name
          ) { id schemaVersionId key name }
        }
        """,
        %{
          "organizationId" => organization_id,
          "schemaVersionId" => schema["id"],
          "key" => "customer",
          "name" => "Customer"
        }
      )["addDatasetRecordType"]

    field =
      graphql!(
        conn,
        """
        mutation AddField(
          $organizationId: ID!,
          $recordTypeId: ID!,
          $key: String!,
          $name: String!,
          $valueFamily: String!,
          $cardinality: String!,
          $required: Boolean!
        ) {
          addDatasetFieldDefinition(
            organizationId: $organizationId,
            recordTypeId: $recordTypeId,
            key: $key,
            name: $name,
            valueFamily: $valueFamily,
            cardinality: $cardinality,
            required: $required
          ) { id recordTypeId key name valueFamily cardinality required }
        }
        """,
        %{
          "organizationId" => organization_id,
          "recordTypeId" => root["id"],
          "key" => "name",
          "name" => "Name",
          "valueFamily" => "text",
          "cardinality" => "single",
          "required" => true
        }
      )["addDatasetFieldDefinition"]

    assert field["valueFamily"] == "text"
    assert field["required"]

    published =
      graphql!(
        conn,
        """
        mutation Publish(
          $organizationId: ID!,
          $schemaVersionId: ID!,
          $rootRecordTypeId: ID!
        ) {
          publishDatasetSchemaVersion(
            organizationId: $organizationId,
            schemaVersionId: $schemaVersionId,
            rootRecordTypeId: $rootRecordTypeId
          ) { id state publishedAt rootRecordTypeId }
        }
        """,
        %{
          "organizationId" => organization_id,
          "schemaVersionId" => schema["id"],
          "rootRecordTypeId" => root["id"]
        }
      )["publishDatasetSchemaVersion"]

    assert published["state"] == "published"
    assert published["rootRecordTypeId"] == root["id"]

    reads =
      graphql!(
        conn,
        """
        query ReadSchema($organizationId: ID!, $schemaVersionId: ID!, $recordTypeId: ID!) {
          datasets(organizationId: $organizationId) { id key name }
          datasetSchemaVersion(
            organizationId: $organizationId,
            schemaVersionId: $schemaVersionId
          ) { id state rootRecordTypeId }
          datasetRecordTypes(
            organizationId: $organizationId,
            schemaVersionId: $schemaVersionId
          ) { id key name }
          datasetFieldDefinitions(
            organizationId: $organizationId,
            recordTypeId: $recordTypeId
          ) { id key valueFamily cardinality required }
        }
        """,
        %{
          "organizationId" => organization_id,
          "schemaVersionId" => schema["id"],
          "recordTypeId" => root["id"]
        }
      )

    assert [%{"id" => dataset_id, "key" => "customers"}] = reads["datasets"]
    assert dataset_id == dataset["id"]
    assert reads["datasetSchemaVersion"]["state"] == "published"
    assert [%{"id" => root_id, "key" => "customer"}] = reads["datasetRecordTypes"]
    assert root_id == root["id"]

    assert [%{"id" => field_id, "valueFamily" => "text", "cardinality" => "single"}] =
             reads["datasetFieldDefinitions"]

    assert field_id == field["id"]
  end

  defp graphql!(conn, query, variables) do
    response =
      conn |> post("/graphql", %{query: query, variables: variables}) |> json_response(200)

    assert is_nil(response["errors"]), inspect(response["errors"])
    response["data"]
  end
end
