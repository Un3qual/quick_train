defmodule QuickTrainWeb.GraphqlApiTest do
  use QuickTrain.ConnCase, async: false

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
    begin_query = """
    query {
      beginOidcLogin(callbackKey: "desktop") {
        authorizationUri
        state
        clientProof
        expiresAt
      }
    }
    """

    begin_conn = post(conn, "/graphql", %{query: begin_query})
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

  test "public GraphQL roots contain only OIDC begin and exchange", %{conn: conn} do
    query = """
    {
      __schema {
        queryType { fields { name } }
        mutationType { fields { name } }
        types { name }
      }
    }
    """

    response = conn |> post("/graphql", %{query: query}) |> json_response(200)
    schema = response["data"]["__schema"]

    assert schema["queryType"]["fields"] == [%{"name" => "beginOidcLogin"}]
    assert schema["mutationType"]["fields"] == [%{"name" => "exchangeOidcLogin"}]

    type_names = MapSet.new(schema["types"], & &1["name"])
    refute MapSet.member?(type_names, "User")
    refute MapSet.member?(type_names, "Session")
    refute MapSet.member?(type_names, "OidcLoginTransaction")
    refute MapSet.member?(type_names, "ExternalIdentity")
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
