defmodule QuickTrain.OidcLoginTest do
  use QuickTrain.DataCase, async: false

  require Ash.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias QuickTrain.Accounts
  alias QuickTrain.Accounts.{Oidc, OidccProvider, OidcLoginTransaction}
  alias QuickTrain.Authentication

  setup do
    original_authentication = Application.get_env(:quick_train, :authentication)
    original_test_pid = Application.get_env(:quick_train, :oidc_test_pid)
    original_exchange_result = Application.get_env(:quick_train, :oidc_test_exchange_result)
    original_human_oidc = Application.get_env(:quick_train, :human_oidc)

    limiter_namespace = "test-#{System.unique_integer([:positive])}"

    Application.put_env(:quick_train, :oidc_test_pid, self())
    Application.delete_env(:quick_train, :oidc_test_exchange_result)
    Application.put_env(:quick_train, :human_oidc, issuer: "https://issuer.example.test")

    Application.put_env(
      :quick_train,
      :authentication,
      Keyword.merge(original_authentication || [],
        oidc_provider: QuickTrain.TestOidcProvider,
        oidc_callbacks: [desktop: "http://127.0.0.1:4173/oidc/callback"],
        oidc_begin_limiter_namespace: limiter_namespace,
        oidc_begin_window_ms: 60_000,
        oidc_begin_global_limit: 100,
        oidc_begin_network_limit: 10,
        oidc_outstanding_limit: 100,
        oidc_transaction_ttl_seconds: 300,
        oidc_replay_retention_seconds: 86_400
      )
    )

    on_exit(fn ->
      restore_env(:authentication, original_authentication)
      restore_env(:oidc_test_pid, original_test_pid)
      restore_env(:oidc_test_exchange_result, original_exchange_result)
      restore_env(:human_oidc, original_human_oidc)
    end)

    :ok
  end

  test "begin creates unpredictable client-bound material for a trusted callback" do
    result = begin_oidc_login!("desktop", "198.51.100.10")

    assert is_binary(result.state)
    assert is_binary(result.client_proof)
    assert byte_size(Base.url_decode64!(result.state, padding: false)) == 32
    assert byte_size(Base.url_decode64!(result.client_proof, padding: false)) == 32
    assert result.authorization_uri =~ "https://issuer.example.test/authorize?"

    assert_receive {:oidc_authorization, provider_options}
    assert provider_options.redirect_uri == "http://127.0.0.1:4173/oidc/callback"
    assert provider_options.state == result.state
    assert byte_size(Base.url_decode64!(provider_options.nonce, padding: false)) == 32
    assert byte_size(Base.url_decode64!(provider_options.pkce_verifier, padding: false)) >= 32

    expected_challenge =
      provider_options.pkce_verifier
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.url_encode64(padding: false)

    assert provider_options.code_challenge == expected_challenge

    transaction = Accounts.get_oidc_login!(:crypto.hash(:sha256, result.state))
    assert transaction.state_hash == :crypto.hash(:sha256, result.state)
    assert transaction.nonce_hash == :crypto.hash(:sha256, provider_options.nonce)
    assert transaction.redemption_secret_hash == :crypto.hash(:sha256, result.client_proof)
    assert transaction.code_verifier == provider_options.pkce_verifier
    assert transaction.callback_key == "desktop"
    assert transaction.callback_uri == provider_options.redirect_uri
    refute Map.has_key?(result, :nonce)
    refute Map.has_key?(result, :pkce_verifier)
  end

  test "independent begin requests never reuse state, proof, nonce, or PKCE material" do
    first = begin_oidc_login!("desktop", "198.51.100.13")
    assert_receive {:oidc_authorization, first_options}
    second = begin_oidc_login!("desktop", "198.51.100.14")
    assert_receive {:oidc_authorization, second_options}

    refute first.state == second.state
    refute first.client_proof == second.client_proof
    refute first_options.nonce == second_options.nonce
    refute first_options.pkce_verifier == second_options.pkce_verifier
    refute first_options.code_challenge == second_options.code_challenge
  end

  test "begin rejects untrusted callback keys before persistence or provider work" do
    before_count = Ash.count!(QuickTrain.Accounts.OidcLoginTransaction, authorize?: false)

    assert {:error, error} = begin_oidc_login("attacker", "198.51.100.11")
    assert Exception.message(error) =~ "untrusted_callback"

    assert Ash.count!(QuickTrain.Accounts.OidcLoginTransaction, authorize?: false) == before_count
    refute_receive {:oidc_authorization, _options}
  end

  test "begin enforces network admission before persistence or provider work" do
    authentication = Application.fetch_env!(:quick_train, :authentication)

    Application.put_env(
      :quick_train,
      :authentication,
      Keyword.put(authentication, :oidc_begin_network_limit, 1)
    )

    _first = begin_oidc_login!("desktop", "198.51.100.12")
    assert_receive {:oidc_authorization, _options}
    before_count = Ash.count!(QuickTrain.Accounts.OidcLoginTransaction, authorize?: false)

    assert {:error, error} = begin_oidc_login("desktop", "198.51.100.12")
    assert Exception.message(error) =~ "rate_limited"

    assert Ash.count!(QuickTrain.Accounts.OidcLoginTransaction, authorize?: false) == before_count
    refute_receive {:oidc_authorization, _options}
  end

  test "begin enforces the outstanding-state cap before provider work" do
    authentication = Application.fetch_env!(:quick_train, :authentication)

    Application.put_env(
      :quick_train,
      :authentication,
      Keyword.put(authentication, :oidc_outstanding_limit, 1)
    )

    _first = begin_oidc_login!("desktop", "198.51.100.15")
    assert_receive {:oidc_authorization, _options}
    before_count = Ash.count!(QuickTrain.Accounts.OidcLoginTransaction, authorize?: false)

    assert {:error, error} = begin_oidc_login("desktop", "198.51.100.16")
    assert Exception.message(error) =~ "outstanding_limit"
    assert Ash.count!(QuickTrain.Accounts.OidcLoginTransaction, authorize?: false) == before_count
    refute_receive {:oidc_authorization, _options}
  end

  @tag :unboxed_db
  test "concurrent begins reserve outstanding-state capacity across database connections" do
    authentication = Application.fetch_env!(:quick_train, :authentication)
    callback_key = "concurrent-#{System.unique_integer([:positive])}"

    Application.put_env(
      :quick_train,
      :authentication,
      authentication
      |> Keyword.put(:oidc_callbacks, [
        {callback_key, "http://127.0.0.1:4173/oidc/callback"}
      ])
      |> Keyword.put(:oidc_outstanding_limit, 1)
      |> Keyword.put(:oidc_begin_network_limit, 100)
    )

    try do
      results = concurrent_begins(callback_key, 12)

      assert Enum.count(results, &match?({:ok, _result}, &1)) == 1
      assert Enum.count(results, &match?({:error, _error}, &1)) == 11
      assert count_non_expired_transactions(callback_key) == 1
    after
      delete_transactions(callback_key)
    end
  end

  test "exchange verifies the separate client proof before provider contact" do
    login = begin_oidc_login!("desktop", "198.51.100.20")
    assert_receive {:oidc_authorization, _options}

    assert {:error, error} =
             Authentication.exchange_oidc_login("provider-code", login.state, "wrong-proof")

    assert Exception.message(error) =~ "invalid_oidc_exchange"
    refute_receive {:oidc_exchange, _code, _options}

    transaction = Accounts.get_oidc_login!(:crypto.hash(:sha256, login.state))
    assert transaction.status == "pending"
  end

  test "client callback handoff exchanges code and state into one bearer session" do
    login = begin_oidc_login!("desktop", "198.51.100.21")
    assert_receive {:oidc_authorization, begin_options}

    result =
      Authentication.exchange_oidc_login!("provider-code", login.state, login.client_proof)

    assert_receive {:oidc_exchange, "provider-code", exchange_options}
    assert exchange_options.redirect_uri == begin_options.redirect_uri
    assert exchange_options.pkce_verifier == begin_options.pkce_verifier
    assert exchange_options.nonce == begin_options.nonce

    assert is_binary(result.token)
    assert byte_size(Base.url_decode64!(result.token, padding: false)) == 32
    assert result.user.email == "new.user@example.test"
    assert result.user.display_name == "New User"

    transaction = Accounts.get_oidc_login!(:crypto.hash(:sha256, login.state))
    assert transaction.status == "consumed"

    session = Accounts.get_session_by_token_hash!(:crypto.hash(:sha256, result.token))
    assert session.id == result.session_id
    assert session.user_id == result.user.id

    identity =
      Accounts.get_external_identity!("https://issuer.example.test", "subject-1")

    assert identity.user_id == result.user.id
    assert identity.status == "active"
  end

  test "a provider failure leaves the winning claim permanently unusable" do
    Application.put_env(:quick_train, :oidc_test_exchange_result, {:error, :invalid_code})

    login = begin_oidc_login!("desktop", "198.51.100.22")
    assert_receive {:oidc_authorization, _options}

    assert {:error, first_error} =
             Authentication.exchange_oidc_login("invalid-code", login.state, login.client_proof)

    assert Exception.message(first_error) =~ "provider_exchange_failed"
    assert_receive {:oidc_exchange, "invalid-code", _options}

    transaction = Accounts.get_oidc_login!(:crypto.hash(:sha256, login.state))
    assert transaction.status == "exchanging"

    assert {:error, second_error} =
             Authentication.exchange_oidc_login("invalid-code", login.state, login.client_proof)

    assert Exception.message(second_error) =~ "invalid_oidc_exchange"
    refute_receive {:oidc_exchange, "invalid-code", _options}
  end

  test "existing identities resolve only by issuer and subject without email relinking" do
    user = Accounts.register_user!("original@example.test", "Original")

    _identity =
      Accounts.create_external_identity!(%{
        user_id: user.id,
        issuer: "https://issuer.example.test",
        subject: "subject-1",
        claims: %{"email" => "original@example.test"}
      })

    Application.put_env(
      :quick_train,
      :oidc_test_exchange_result,
      {:ok,
       %{
         "iss" => "https://issuer.example.test",
         "sub" => "subject-1",
         "email" => "someone-else@example.test",
         "email_verified" => true,
         "name" => "Someone Else"
       }}
    )

    login = begin_oidc_login!("desktop", "198.51.100.23")
    assert_receive {:oidc_authorization, _options}

    result = Authentication.exchange_oidc_login!("provider-code", login.state, login.client_proof)

    assert result.user.id == user.id
    assert result.user.email == "original@example.test"
    assert Ash.count!(QuickTrain.Accounts.User, authorize?: false) == 1
  end

  test "a new subject cannot link to an existing account by email" do
    existing_user = Accounts.register_user!("new.user@example.test", "Existing")
    login = begin_oidc_login!("desktop", "198.51.100.24")
    assert_receive {:oidc_authorization, _options}

    assert {:error, error} =
             Authentication.exchange_oidc_login("provider-code", login.state, login.client_proof)

    assert Exception.message(error) =~ "account_linking_conflict"
    assert Ash.count!(QuickTrain.Accounts.User, authorize?: false) == 1

    assert Accounts.get_external_identity(
             "https://issuer.example.test",
             "subject-1",
             authorize?: false,
             not_found_error?: false
           ) == {:ok, nil}

    assert Ash.count!(QuickTrain.Accounts.Session, authorize?: false) == 0

    transaction = Accounts.get_oidc_login!(:crypto.hash(:sha256, login.state))
    assert transaction.status == "exchanging"
    assert existing_user.email == "new.user@example.test"
  end

  test "new accounts fall back to the normalized email local part for display name" do
    Application.put_env(
      :quick_train,
      :oidc_test_exchange_result,
      {:ok,
       %{
         "iss" => "https://issuer.example.test",
         "sub" => "subject-fallback",
         "email" => "  Fallback.Name@Example.test ",
         "email_verified" => true,
         "name" => "  ",
         "preferred_username" => ""
       }}
    )

    login = begin_oidc_login!("desktop", "198.51.100.25")
    assert_receive {:oidc_authorization, _options}

    result = Authentication.exchange_oidc_login!("provider-code", login.state, login.client_proof)

    assert result.user.email == "fallback.name@example.test"
    assert result.user.display_name == "fallback.name"
  end

  test "an inactive linked user is denied without implicit reactivation" do
    user = Accounts.register_user!("inactive@example.test", "Inactive")

    _identity =
      Accounts.create_external_identity!(%{
        user_id: user.id,
        issuer: "https://issuer.example.test",
        subject: "subject-1",
        claims: %{}
      })

    disabled_user =
      user
      |> Ash.Changeset.for_update(:set_status, %{status: "disabled"}, authorize?: false)
      |> Ash.update!()

    login = begin_oidc_login!("desktop", "198.51.100.26")
    assert_receive {:oidc_authorization, _options}

    assert {:error, error} =
             Authentication.exchange_oidc_login("provider-code", login.state, login.client_proof)

    assert Exception.message(error) =~ "inactive_account"
    assert Ash.count!(QuickTrain.Accounts.Session, authorize?: false) == 0
    assert Accounts.get_user!(disabled_user.id).status == "disabled"
  end

  test "an inactive external identity is denied without implicit reactivation" do
    user = Accounts.register_user!("inactive-identity@example.test", "Inactive Identity")

    identity =
      Accounts.create_external_identity!(%{
        user_id: user.id,
        issuer: "https://issuer.example.test",
        subject: "subject-1",
        claims: %{}
      })

    inactive_identity =
      identity
      |> Ash.Changeset.for_update(:set_status, %{status: "inactive"}, authorize?: false)
      |> Ash.update!()

    login = begin_oidc_login!("desktop", "198.51.100.31")
    assert_receive {:oidc_authorization, _options}

    assert {:error, error} =
             Authentication.exchange_oidc_login("provider-code", login.state, login.client_proof)

    assert Exception.message(error) =~ "inactive_account"
    assert Ash.count!(QuickTrain.Accounts.Session, authorize?: false) == 0

    persisted =
      Accounts.get_external_identity!("https://issuer.example.test", "subject-1")

    assert persisted.id == inactive_identity.id
    assert persisted.status == "inactive"
  end

  test "new identities require a nonempty provider-verified email" do
    Application.put_env(
      :quick_train,
      :oidc_test_exchange_result,
      {:ok,
       %{
         "iss" => "https://issuer.example.test",
         "sub" => "subject-without-verified-email",
         "email" => "unverified@example.test",
         "email_verified" => false
       }}
    )

    login = begin_oidc_login!("desktop", "198.51.100.32")
    assert_receive {:oidc_authorization, _options}

    assert {:error, error} =
             Authentication.exchange_oidc_login("provider-code", login.state, login.client_proof)

    assert Exception.message(error) =~ "verified_email_required"
    assert Ash.count!(QuickTrain.Accounts.User, authorize?: false) == 0
    assert Ash.count!(QuickTrain.Accounts.ExternalIdentity, authorize?: false) == 0
    assert Ash.count!(QuickTrain.Accounts.Session, authorize?: false) == 0
  end

  test "provider issuer must match the configured canonical issuer" do
    Application.put_env(
      :quick_train,
      :oidc_test_exchange_result,
      {:ok,
       %{
         "iss" => "https://other-issuer.example.test",
         "sub" => "subject-1",
         "email" => "wrong-issuer@example.test",
         "email_verified" => true
       }}
    )

    login = begin_oidc_login!("desktop", "198.51.100.33")
    assert_receive {:oidc_authorization, _options}

    assert {:error, error} =
             Authentication.exchange_oidc_login("provider-code", login.state, login.client_proof)

    assert Exception.message(error) =~ "invalid_provider_identity"
    assert Ash.count!(QuickTrain.Accounts.Session, authorize?: false) == 0
  end

  test "concurrent exchanges claim one transaction before contacting the provider" do
    login = begin_oidc_login!("desktop", "198.51.100.27")
    assert_receive {:oidc_authorization, _options}

    results =
      1..2
      |> Enum.map(fn _attempt ->
        Task.async(fn ->
          Authentication.exchange_oidc_login("provider-code", login.state, login.client_proof)
        end)
      end)
      |> Task.await_many()

    assert Enum.count(results, &match?({:ok, _result}, &1)) == 1
    assert Enum.count(results, &match?({:error, _error}, &1)) == 1
    assert_receive {:oidc_exchange, "provider-code", _options}
    refute_receive {:oidc_exchange, "provider-code", _options}
    assert Ash.count!(QuickTrain.Accounts.Session, authorize?: false) == 1

    transaction = Accounts.get_oidc_login!(:crypto.hash(:sha256, login.state))
    assert transaction.status == "consumed"
  end

  test "concurrent first logins leave one complete user and identity graph" do
    first_login = begin_oidc_login!("desktop", "198.51.100.28")
    second_login = begin_oidc_login!("desktop", "198.51.100.29")
    assert_receive {:oidc_authorization, _options}
    assert_receive {:oidc_authorization, _options}

    results =
      [first_login, second_login]
      |> Enum.map(fn login ->
        Task.async(fn ->
          Authentication.exchange_oidc_login("provider-code", login.state, login.client_proof)
        end)
      end)
      |> Task.await_many()

    assert Enum.any?(results, &match?({:ok, _result}, &1))
    assert Ash.count!(QuickTrain.Accounts.User, authorize?: false) == 1
    assert Ash.count!(QuickTrain.Accounts.ExternalIdentity, authorize?: false) == 1

    identity =
      Accounts.get_external_identity!("https://issuer.example.test", "subject-1")

    user = Accounts.get_user!(identity.user_id)
    assert user.email == "new.user@example.test"

    success_count = Enum.count(results, &match?({:ok, _result}, &1))
    assert Ash.count!(QuickTrain.Accounts.Session, authorize?: false) == success_count
  end

  test "provider discovery endpoints must all be HTTPS before they are used" do
    secure_configuration = %Oidcc.ProviderConfiguration{
      issuer: "https://issuer.example.test",
      authorization_endpoint: "https://issuer.example.test/authorize",
      token_endpoint: "https://issuer.example.test/token",
      jwks_uri: "https://issuer.example.test/jwks",
      userinfo_endpoint: "https://issuer.example.test/userinfo",
      pushed_authorization_request_endpoint: :undefined,
      mtls_endpoint_aliases: %{}
    }

    assert OidccProvider.secure_provider_configuration?(secure_configuration)

    refute OidccProvider.secure_provider_configuration?(%{
             secure_configuration
             | token_endpoint: "http://issuer.example.test/token"
           })

    refute OidccProvider.secure_provider_configuration?(%{
             secure_configuration
             | jwks_uri: "http://127.0.0.1/jwks"
           })

    refute OidccProvider.secure_provider_configuration?(%{
             secure_configuration
             | authorization_endpoint: "http://issuer.example.test/authorize"
           })
  end

  test "production callback and issuer policy rejects every cleartext endpoint" do
    refute Oidc.secure_callback_uri?("http://client.example.test/callback", false)
    refute Oidc.secure_callback_uri?("http://127.0.0.1/callback", false)
    assert Oidc.secure_callback_uri?("https://client.example.test/callback", false)

    Application.put_env(:quick_train, :human_oidc,
      issuer: "http://issuer.example.test",
      client_id: "client-id",
      client_secret: "client-secret"
    )

    assert {:error, :insecure_provider_endpoint} =
             OidccProvider.authorization_url(%{
               redirect_uri: "https://client.example.test/callback",
               state: "state",
               nonce: "nonce",
               pkce_verifier: String.duplicate("v", 43),
               require_pkce: true,
               scopes: ["openid"]
             })
  end

  defp begin_oidc_login(callback_key, network_source) do
    Authentication.begin_oidc_login(callback_key,
      context: %{authentication_network_source: network_source}
    )
  end

  defp begin_oidc_login!(callback_key, network_source) do
    Authentication.begin_oidc_login!(callback_key,
      context: %{authentication_network_source: network_source}
    )
  end

  defp concurrent_begins(callback_key, count) do
    parent = self()

    tasks =
      for attempt <- 1..count do
        Task.async(fn -> await_concurrent_begin(parent, callback_key, attempt) end)
      end

    task_pids =
      for _attempt <- 1..count do
        assert_receive {:begin_ready, task_pid}
        task_pid
      end

    Enum.each(task_pids, &send(&1, :begin))
    Task.await_many(tasks, 15_000)
  end

  defp await_concurrent_begin(parent, callback_key, attempt) do
    send(parent, {:begin_ready, self()})

    receive do
      :begin ->
        Sandbox.unboxed_run(Repo, fn ->
          begin_oidc_login(callback_key, "198.51.100.#{attempt}")
        end)
    end
  end

  defp count_non_expired_transactions(callback_key) do
    now = DateTime.utc_now()

    Sandbox.unboxed_run(Repo, fn ->
      OidcLoginTransaction
      |> Ash.Query.filter(callback_key == ^callback_key and expires_at > ^now)
      |> Ash.count!(authorize?: false)
    end)
  end

  defp delete_transactions(callback_key) do
    Sandbox.unboxed_run(Repo, fn ->
      result =
        OidcLoginTransaction
        |> Ash.Query.filter(callback_key == ^callback_key)
        |> Ash.bulk_destroy(:discard, %{},
          authorize?: false,
          strategy: [:atomic],
          return_errors?: true
        )

      case result do
        %Ash.BulkResult{status: :success} -> :ok
        %Ash.BulkResult{errors: errors} -> raise Ash.Error.to_error_class(errors)
      end
    end)
  end

  defp restore_env(key, nil), do: Application.delete_env(:quick_train, key)
  defp restore_env(key, value), do: Application.put_env(:quick_train, key, value)
end
