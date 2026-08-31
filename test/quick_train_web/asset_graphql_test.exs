defmodule QuickTrainWeb.AssetGraphqlTest do
  use QuickTrain.ConnCase, async: false

  alias QuickTrain.{Accounts, Datasets}
  alias QuickTrain.Assets.Storage.Test, as: TestStorage

  setup %{conn: conn} do
    :ok = TestStorage.reset()

    manager = Accounts.register_user!("graphql-assets@example.test", "GraphQL Assets")
    graph = Accounts.bootstrap_first_manager!(manager.id, "graphql-assets", "GraphQL Assets")
    Datasets.grant_product_capabilities!(graph.organization.id, manager.id)
    session = Accounts.issue_bearer_session!(manager.id)

    authenticated_conn = put_req_header(conn, "authorization", "Bearer #{session.token}")

    %{conn: authenticated_conn, manager: manager, graph: graph}
  end

  test "authenticated asset workflow exposes only safe typed results", %{conn: conn, graph: graph} do
    content = "graphql asset"

    registration =
      graphql!(
        conn,
        """
        mutation Register($organizationId: ID!, $sha256: String!, $byteSize: Int!, $mediaType: String!) {
          registerAsset(
            organizationId: $organizationId,
            sha256: $sha256,
            byteSize: $byteSize,
            mediaType: $mediaType
          ) {
            reused
            asset { id organizationId state sha256 byteSize mediaType }
            uploadAccess { method uri expiresAt maxBytes cacheControl referrerPolicy headers }
          }
        }
        """,
        %{
          "organizationId" => graph.organization.id,
          "sha256" => sha256(content),
          "byteSize" => byte_size(content),
          "mediaType" => "text/plain"
        }
      )["registerAsset"]

    assert registration["reused"] == false
    assert registration["asset"]["state"] == "PENDING"
    assert registration["uploadAccess"]["method"] == "PUT"
    assert registration["uploadAccess"]["maxBytes"] == byte_size(content)
    assert registration["uploadAccess"]["uri"] =~ "https://storage.quicktrain.test/"

    refute Map.has_key?(registration["asset"], "stagingKey")
    refute Map.has_key?(registration["asset"], "sealedKey")
    refute Map.has_key?(registration["asset"], "operationClaimId")

    assert :ok =
             TestStorage.put_staging(
               %{uri: registration["uploadAccess"]["uri"]},
               content
             )

    finalized =
      graphql!(
        conn,
        """
        mutation Finalize($assetId: ID!, $organizationId: ID!) {
          finalizeAsset(assetId: $assetId, organizationId: $organizationId) {
            asset { id state failureReason canonicalAssetId }
            canonicalAsset { id state }
          }
        }
        """,
        %{
          "assetId" => registration["asset"]["id"],
          "organizationId" => graph.organization.id
        }
      )["finalizeAsset"]

    assert finalized["asset"]["state"] == "READY"
    assert finalized["canonicalAsset"]["id"] == finalized["asset"]["id"]

    asset =
      graphql!(
        conn,
        """
        query Asset($assetId: ID!, $organizationId: ID!) {
          asset(assetId: $assetId, organizationId: $organizationId) {
            id organizationId state sha256 byteSize mediaType width height failureReason canonicalAssetId
          }
        }
        """,
        %{
          "assetId" => finalized["asset"]["id"],
          "organizationId" => graph.organization.id
        }
      )["asset"]

    assert asset["state"] == "READY"

    access =
      graphql!(
        conn,
        """
        query AssetAccess($assetId: ID!, $organizationId: ID!) {
          assetAccess(assetId: $assetId, organizationId: $organizationId) {
            asset { id state }
            readAccess { method uri expiresAt cacheControl referrerPolicy }
          }
        }
        """,
        %{
          "assetId" => finalized["asset"]["id"],
          "organizationId" => graph.organization.id
        }
      )["assetAccess"]

    assert access["readAccess"]["method"] == "GET"
    assert {:ok, ^content} = TestStorage.read_sealed(%{uri: access["readAccess"]["uri"]})
  end

  test "the GraphQL root is deliberate and has no generic asset mutation", %{conn: conn} do
    schema =
      graphql!(conn, """
      {
        __schema {
          queryType { fields { name } }
          mutationType { fields { name } }
          types { name fields { name } }
        }
      }
      """)
      |> Map.fetch!("__schema")

    query_names = MapSet.new(schema["queryType"]["fields"], & &1["name"])
    mutation_names = MapSet.new(schema["mutationType"]["fields"], & &1["name"])

    assert MapSet.subset?(MapSet.new(["asset", "assetAccess"]), query_names)
    assert MapSet.subset?(MapSet.new(["registerAsset", "finalizeAsset"]), mutation_names)

    refute Enum.any?(mutation_names, &(&1 in ["createAsset", "updateAsset", "destroyAsset"]))

    asset_type = Enum.find(schema["types"], &(&1["name"] == "Asset"))
    asset_fields = MapSet.new(asset_type["fields"], & &1["name"])

    refute MapSet.member?(asset_fields, "stagingKey")
    refute MapSet.member?(asset_fields, "sealedKey")
    refute MapSet.member?(asset_fields, "operationClaimId")
  end

  defp graphql!(conn, query, variables \\ %{}) do
    response =
      conn |> post("/graphql", %{query: query, variables: variables}) |> json_response(200)

    assert is_nil(response["errors"]), inspect(response["errors"])
    response["data"]
  end

  defp sha256(content),
    do: Base.encode16(:crypto.hash(:sha256, content), case: :lower)
end
