defmodule QuickTrainWeb.GraphqlApiTest do
  use QuickTrain.ConnCase, async: false

  import ExUnit.CaptureLog

  setup do
    original_authentication = Application.get_env(:quick_train, :authentication)
    original_test_pid = Application.get_env(:quick_train, :oidc_test_pid)
    original_human_oidc = Application.get_env(:quick_train, :human_oidc)

    Application.put_env(:quick_train, :oidc_test_pid, self())
    Application.put_env(:quick_train, :human_oidc, issuer: "https://issuer.example.test")

    Application.put_env(
      :quick_train,
      :authentication,
      Keyword.merge(original_authentication || [],
        oidc_provider: QuickTrain.TestOidcProvider,
        oidc_callbacks: [desktop: "http://127.0.0.1:4173/oidc/callback"],
        oidc_begin_limiter_namespace: "graphql-#{System.unique_integer([:positive])}"
      )
    )

    on_exit(fn ->
      restore_env(:authentication, original_authentication)
      restore_env(:oidc_test_pid, original_test_pid)
      restore_env(:human_oidc, original_human_oidc)
    end)

    :ok
  end

  test "client-owned callback hands provider code and state to GraphQL exchange", %{conn: conn} do
    begin_mutation = """
    mutation {
      beginOidcLogin(callbackKey: "desktop") {
        authorizationUri
        state
        clientProof
        expiresAt
      }
    }
    """

    begin_conn = post(conn, "/graphql", %{query: begin_mutation})
    begin_payload = json_response(begin_conn, 200)["data"]["beginOidcLogin"]

    assert begin_payload["authorizationUri"] =~ "https://issuer.example.test/authorize?"
    assert is_binary(begin_payload["state"])
    assert is_binary(begin_payload["clientProof"])
    assert is_binary(begin_payload["expiresAt"])
    assert get_resp_header(begin_conn, "cache-control") == ["no-store"]
    assert_receive {:oidc_authorization, _options}

    exchange_query = """
    mutation Exchange($code: String!, $state: String!, $clientProof: String!) {
      exchangeOidcLogin(code: $code, state: $state, clientProof: $clientProof) {
        token
        sessionId
        expiresAt
      }
    }
    """

    exchange_conn =
      post(conn, "/graphql", %{
        query: exchange_query,
        variables: %{
          "code" => "provider-code",
          "state" => begin_payload["state"],
          "clientProof" => begin_payload["clientProof"]
        }
      })

    exchange_payload = json_response(exchange_conn, 200)["data"]["exchangeOidcLogin"]
    assert is_binary(exchange_payload["token"])
    assert is_binary(exchange_payload["sessionId"])
    assert is_binary(exchange_payload["expiresAt"])
    assert get_resp_header(exchange_conn, "cache-control") == ["no-store"]
    assert_receive {:oidc_exchange, "provider-code", _options}
  end

  test "public GraphQL roots contain only deliberate authenticated product operations", %{
    conn: conn
  } do
    query = """
    {
      __schema {
        queryType { fields { name args { name } } }
        mutationType { fields { name args { name } } }
        types { name kind enumValues { name } }
      }
    }
    """

    response = conn |> post("/graphql", %{query: query}) |> json_response(200)
    schema = response["data"]["__schema"]

    queries =
      Map.new(schema["queryType"]["fields"], fn field ->
        {field["name"], MapSet.new(field["args"], & &1["name"])}
      end)

    assert queries == %{
             "apiVersion" => MapSet.new(),
             "asset" => MapSet.new(["assetId", "organizationId"]),
             "assetAccess" => MapSet.new(["assetId", "organizationId"]),
             "datasetFieldDefinitions" =>
               MapSet.new([
                 "after",
                 "before",
                 "first",
                 "last",
                 "organizationId",
                 "recordTypeId"
               ]),
             "datasetImport" => MapSet.new(["importId", "organizationId"]),
             "datasetImportRows" =>
               MapSet.new([
                 "after",
                 "before",
                 "first",
                 "importId",
                 "last",
                 "organizationId"
               ]),
             "datasetItemRevisions" =>
               MapSet.new([
                 "after",
                 "before",
                 "first",
                 "itemId",
                 "last",
                 "organizationId"
               ]),
             "datasetItems" =>
               MapSet.new([
                 "after",
                 "before",
                 "datasetId",
                 "first",
                 "last",
                 "organizationId"
               ]),
             "datasetRecordTypes" =>
               MapSet.new([
                 "after",
                 "before",
                 "first",
                 "last",
                 "organizationId",
                 "schemaVersionId"
               ]),
             "datasetSchemaVersion" => MapSet.new(["organizationId", "schemaVersionId"]),
             "datasetValues" =>
               MapSet.new([
                 "after",
                 "before",
                 "first",
                 "last",
                 "organizationId",
                 "revisionId"
               ]),
             "datasets" => MapSet.new(["after", "before", "first", "last", "organizationId"])
           }

    mutations =
      Map.new(schema["mutationType"]["fields"], fn field ->
        {field["name"], MapSet.new(field["args"], & &1["name"])}
      end)

    assert mutations == %{
             "addDatasetFieldDefinition" =>
               MapSet.new([
                 "cardinality",
                 "key",
                 "name",
                 "organizationId",
                 "recordTypeId",
                 "required",
                 "valueFamily"
               ]),
             "addDatasetRecordType" =>
               MapSet.new(["key", "name", "organizationId", "schemaVersionId"]),
             "appendDatasetImportRow" =>
               MapSet.new([
                 "externalKey",
                 "importId",
                 "organizationId",
                 "rowKey",
                 "sourcePosition",
                 "values"
               ]),
             "beginOidcLogin" => MapSet.new(["callbackKey"]),
             "createDataset" => MapSet.new(["input"]),
             "createDatasetSchemaVersion" => MapSet.new(["datasetId", "organizationId"]),
             "exchangeOidcLogin" => MapSet.new(["clientProof", "code", "state"]),
             "registerAsset" => MapSet.new(["organizationId", "sha256", "byteSize", "mediaType"]),
             "finalizeAsset" => MapSet.new(["assetId", "organizationId"]),
             "finalizeDatasetImport" => MapSet.new(["importId", "organizationId"]),
             "openDatasetImport" =>
               MapSet.new([
                 "datasetId",
                 "idempotencyKey",
                 "organizationId",
                 "schemaVersionId"
               ]),
             "publishDatasetSchemaVersion" =>
               MapSet.new(["organizationId", "rootRecordTypeId", "schemaVersionId"]),
             "removeDatasetFieldDefinition" =>
               MapSet.new(["fieldDefinitionId", "organizationId"]),
             "removeDatasetRecordType" => MapSet.new(["organizationId", "recordTypeId"]),
             "updateDatasetFieldDefinition" =>
               MapSet.new([
                 "cardinality",
                 "fieldDefinitionId",
                 "key",
                 "name",
                 "organizationId",
                 "required",
                 "valueFamily"
               ]),
             "updateDatasetRecordType" =>
               MapSet.new(["key", "name", "organizationId", "recordTypeId"])
           }

    type_names = MapSet.new(schema["types"], & &1["name"])
    refute MapSet.member?(type_names, "User")
    refute MapSet.member?(type_names, "Session")
    refute MapSet.member?(type_names, "OidcLoginTransaction")
    refute MapSet.member?(type_names, "ExternalIdentity")

    enum_values =
      schema["types"]
      |> Enum.filter(&(&1["kind"] == "ENUM"))
      |> Map.new(fn type ->
        {type["name"], MapSet.new(type["enumValues"], & &1["name"])}
      end)

    assert Map.take(enum_values, [
             "AssetState",
             "AssetStorageMethod",
             "DatasetFieldCardinality",
             "DatasetImportLifecycle",
             "DatasetImportPhase",
             "DatasetImportRowOutcome",
             "DatasetSchemaState",
             "DatasetValueFamily"
           ]) == %{
             "AssetState" => MapSet.new(~w(DUPLICATE_CONTENT FAILED PENDING READY)),
             "AssetStorageMethod" => MapSet.new(~w(GET PUT)),
             "DatasetFieldCardinality" => MapSet.new(~w(SINGLE)),
             "DatasetImportLifecycle" =>
               MapSet.new(~w(COMPLETED FAILED OPEN PARTIALLY_FAILED PENDING)),
             "DatasetImportPhase" => MapSet.new(~w(OPEN SEALED)),
             "DatasetImportRowOutcome" => MapSet.new(~w(FAILED PENDING SUCCEEDED UNCHANGED)),
             "DatasetSchemaState" => MapSet.new(~w(DRAFT PUBLISHED)),
             "DatasetValueFamily" =>
               MapSet.new(~w(ASSET BOOLEAN DECIMAL INTEGER TEXT UTC_DATETIME))
           }

    version_response = conn |> post("/graphql", %{query: "{ apiVersion }"}) |> json_response(200)
    assert %{"apiVersion" => version} = version_response["data"]
    assert is_binary(version) and version != ""
  end

  test "authentication failures are logged by safe category without request secrets", %{
    conn: conn
  } do
    begin_query =
      "mutation { beginOidcLogin(callbackKey: \"sensitive-callback-key\") { state } }"

    begin_log =
      capture_log(
        [level: :warning, metadata: [:authentication_operation, :authentication_failure]],
        fn ->
          response = conn |> post("/graphql", %{query: begin_query}) |> json_response(200)
          assert [%{"message" => "login unavailable"}] = response["errors"]
        end
      )

    assert begin_log =~ "OIDC login failed"
    assert begin_log =~ "authentication_operation=begin"
    assert begin_log =~ "authentication_failure=untrusted_callback"
    refute begin_log =~ "sensitive-callback-key"

    exchange_query = """
    mutation {
      exchangeOidcLogin(
        code: "sensitive-code",
        state: "sensitive-state",
        clientProof: "sensitive-proof"
      ) { token }
    }
    """

    exchange_log =
      capture_log(
        [level: :warning, metadata: [:authentication_operation, :authentication_failure]],
        fn ->
          response = conn |> post("/graphql", %{query: exchange_query}) |> json_response(200)
          assert [%{"message" => "login exchange failed"}] = response["errors"]
        end
      )

    assert exchange_log =~ "OIDC login failed"
    assert exchange_log =~ "authentication_operation=exchange"
    assert exchange_log =~ "authentication_failure=invalid_oidc_exchange"
    refute exchange_log =~ "sensitive-code"
    refute exchange_log =~ "sensitive-state"
    refute exchange_log =~ "sensitive-proof"
  end

  test "health and GraphiQL stay outside the production-shaped GraphQL surface", %{conn: conn} do
    health_query = conn |> post("/graphql", %{query: "{ health }"}) |> json_response(200)
    assert [%{"message" => message}] = health_query["errors"]
    assert message =~ "Cannot query field \"health\""

    assert conn |> get("/graphiql") |> response(404)
    assert conn |> get("/oidc/callback") |> response(404)

    health_conn = get(conn, "/healthz")
    assert json_response(health_conn, 200) == %{"status" => "ok"}
  end

  test "does not expose a generated REST API", %{conn: conn} do
    conn = get(conn, "/api/v1/users")
    assert response(conn, 404)
  end

  defp restore_env(key, nil), do: Application.delete_env(:quick_train, key)
  defp restore_env(key, value), do: Application.put_env(:quick_train, key, value)
end
