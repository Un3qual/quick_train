defmodule QuickTrainWeb.AuthenticationBoundaryTest do
  use QuickTrain.ConnCase, async: false

  alias QuickTrain.Accounts
  alias QuickTrainWeb.Authentication.{BearerAuthentication, RequestSecurity}

  setup do
    original_authentication = Application.get_env(:quick_train, :authentication)

    on_exit(fn -> restore_env(:authentication, original_authentication) end)

    :ok
  end

  test "cleartext GraphQL and bearer traffic is rejected before parsing or lookup", %{conn: conn} do
    configure_authentication(enforce_https?: true, trusted_proxy_ips: [])

    malformed_conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-forwarded-proto", "https")
      |> post("/graphql", "{")

    assert malformed_conn.status == 426
    assert malformed_conn.halted

    bearer_conn =
      conn
      |> put_req_header("authorization", "Bearer definitely-not-a-token")
      |> get("/healthz")

    assert bearer_conn.status == 426
    assert bearer_conn.halted
  end

  test "cleartext begin and exchange create no login or session material", %{conn: conn} do
    configure_authentication(enforce_https?: true, trusted_proxy_ips: [])

    begin_query = """
    mutation { beginOidcLogin(callbackKey: "desktop") { state clientProof } }
    """

    begin_conn = post(conn, "/graphql", %{query: begin_query})
    assert begin_conn.status == 426
    assert Ash.count!(QuickTrain.Accounts.OidcLoginTransaction, authorize?: false) == 0

    exchange_query = """
    mutation {
      exchangeOidcLogin(code: "code", state: "state", clientProof: "proof") { token }
    }
    """

    exchange_conn = post(conn, "/graphql", %{query: exchange_query})
    assert exchange_conn.status == 426
    assert Ash.count!(QuickTrain.Accounts.Session, authorize?: false) == 0
  end

  test "only a configured direct proxy can supply scheme and network source", %{conn: conn} do
    configure_authentication(enforce_https?: true, trusted_proxy_ips: ["10.0.0.1"])

    trusted_conn =
      conn
      |> Map.put(:remote_ip, {10, 0, 0, 1})
      |> put_req_header("x-forwarded-proto", "https")
      |> put_req_header("x-forwarded-for", "198.51.100.30, 10.0.0.1")
      |> RequestSecurity.call([])

    refute trusted_conn.halted
    assert trusted_conn.assigns.authentication_network_source == "198.51.100.30"

    assert Ash.PlugHelpers.get_context(trusted_conn).authentication_network_source ==
             "198.51.100.30"

    untrusted_conn =
      Phoenix.ConnTest.build_conn(:post, "/graphql", nil)
      |> Map.put(:remote_ip, {192, 0, 2, 40})
      |> put_req_header("x-forwarded-proto", "https")
      |> put_req_header("x-forwarded-for", "198.51.100.99")
      |> RequestSecurity.call([])

    assert untrusted_conn.status == 426
    assert untrusted_conn.assigns.authentication_network_source == "192.0.2.40"
  end

  test "all forwarded GraphQL subpaths require encrypted transport and disable caching" do
    configure_authentication(enforce_https?: true, trusted_proxy_ips: [])

    for path <- ["/graphql/", "/graphql/nested"] do
      secured_conn =
        Phoenix.ConnTest.build_conn(:post, path, nil)
        |> RequestSecurity.call([])

      assert secured_conn.status == 426
      assert secured_conn.halted
      assert get_resp_header(secured_conn, "cache-control") == ["no-store"]
    end
  end

  test "an empty forwarded scheme from a trusted proxy fails closed" do
    configure_authentication(enforce_https?: true, trusted_proxy_ips: ["10.0.0.1"])

    secured_conn =
      Phoenix.ConnTest.build_conn(:post, "/graphql", nil)
      |> Map.put(:remote_ip, {10, 0, 0, 1})
      |> put_req_header("x-forwarded-proto", ",,")
      |> RequestSecurity.call([])

    assert secured_conn.status == 426
    assert secured_conn.halted
  end

  test "a valid bearer installs the active global user as Ash and Absinthe actor", %{conn: conn} do
    configure_authentication(enforce_https?: false)

    user =
      Accounts.register_user!(
        "actor-#{System.unique_integer([:positive])}@example.test",
        "Actor"
      )

    issued = Accounts.issue_bearer_session!(user.id)

    authenticated_conn =
      conn
      |> put_req_header("authorization", "Bearer #{issued.token}")
      |> RequestSecurity.call([])
      |> BearerAuthentication.call([])
      |> AshGraphql.Plug.call([])

    assert Ash.PlugHelpers.get_actor(authenticated_conn).id == user.id
    assert authenticated_conn.private.absinthe.context.actor.id == user.id
    refute Map.has_key?(authenticated_conn.private.absinthe.context, :organization_id)
  end

  test "bearer authentication scheme casing is ignored", %{conn: conn} do
    configure_authentication(enforce_https?: false)

    user =
      Accounts.register_user!(
        "scheme-actor-#{System.unique_integer([:positive])}@example.test",
        "Scheme Actor"
      )

    issued = Accounts.issue_bearer_session!(user.id)

    for scheme <- ["bearer", "BEARER"] do
      authenticated_conn =
        conn
        |> put_req_header("authorization", "#{scheme} #{issued.token}")
        |> RequestSecurity.call([])
        |> BearerAuthentication.call([])

      refute authenticated_conn.halted
      assert Ash.PlugHelpers.get_actor(authenticated_conn).id == user.id
    end
  end

  test "invalid and disabled-user bearer credentials fail closed", %{conn: conn} do
    configure_authentication(enforce_https?: false)

    invalid_conn =
      conn
      |> put_req_header("authorization", "Bearer malformed")
      |> RequestSecurity.call([])
      |> BearerAuthentication.call([])

    assert invalid_conn.status == 401
    assert invalid_conn.halted

    user =
      Accounts.register_user!(
        "disabled-actor-#{System.unique_integer([:positive])}@example.test",
        "Disabled Actor"
      )

    issued = Accounts.issue_bearer_session!(user.id)

    _disabled_user =
      user
      |> Ash.Changeset.for_update(:set_status, %{status: "disabled"}, authorize?: false)
      |> Ash.update!()

    disabled_conn =
      Phoenix.ConnTest.build_conn()
      |> put_req_header("authorization", "Bearer #{issued.token}")
      |> RequestSecurity.call([])
      |> BearerAuthentication.call([])

    assert disabled_conn.status == 401
    assert disabled_conn.halted
  end

  test "unknown, expired, and revoked bearer credentials fail closed" do
    configure_authentication(enforce_https?: false)

    user =
      Accounts.register_user!(
        "lifecycle-actor-#{System.unique_integer([:positive])}@example.test",
        "Lifecycle Actor"
      )

    now = DateTime.utc_now()

    expired_token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    _expired_session =
      Accounts.persist_bearer_session!(%{
        user_id: user.id,
        token_hash: :crypto.hash(:sha256, expired_token),
        authentication_method: "oidc",
        issued_at: DateTime.add(now, -2, :hour),
        expires_at: DateTime.add(now, -1, :hour)
      })

    revoked = Accounts.issue_bearer_session!(user.id)
    revoked_session = Accounts.get_session_by_token_hash!(:crypto.hash(:sha256, revoked.token))
    _revoked_session = Accounts.revoke_session!(revoked_session)

    unknown_token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    for token <- [unknown_token, expired_token, revoked.token] do
      rejected_conn =
        Phoenix.ConnTest.build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> RequestSecurity.call([])
        |> BearerAuthentication.call([])

      assert rejected_conn.status == 401
      assert rejected_conn.halted
    end
  end

  defp configure_authentication(overrides) do
    current = Application.get_env(:quick_train, :authentication, [])
    Application.put_env(:quick_train, :authentication, Keyword.merge(current, overrides))
  end

  defp restore_env(key, nil), do: Application.delete_env(:quick_train, key)
  defp restore_env(key, value), do: Application.put_env(:quick_train, key, value)
end
