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

  test "public GraphQL roots contain only API version and OIDC mutations", %{conn: conn} do
    query = """
    {
      __schema {
        queryType { fields { name args { name } } }
        mutationType { fields { name args { name } } }
        types { name }
      }
    }
    """

    response = conn |> post("/graphql", %{query: query}) |> json_response(200)
    schema = response["data"]["__schema"]

    assert schema["queryType"]["fields"] == [%{"args" => [], "name" => "apiVersion"}]

    assert schema["mutationType"]["fields"] == [
             %{
               "args" => [%{"name" => "callbackKey"}],
               "name" => "beginOidcLogin"
             },
             %{
               "args" => [
                 %{"name" => "clientProof"},
                 %{"name" => "code"},
                 %{"name" => "state"}
               ],
               "name" => "exchangeOidcLogin"
             }
           ]

    type_names = MapSet.new(schema["types"], & &1["name"])
    refute MapSet.member?(type_names, "User")
    refute MapSet.member?(type_names, "Session")
    refute MapSet.member?(type_names, "OidcLoginTransaction")
    refute MapSet.member?(type_names, "ExternalIdentity")

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
