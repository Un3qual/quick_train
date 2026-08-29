defmodule QuickTrain.TestOidcProvider do
  @moduledoc false

  @behaviour QuickTrain.Accounts.OidcProvider

  def authorization_url(options) do
    send(test_pid(), {:oidc_authorization, options})

    query =
      URI.encode_query(%{
        "redirect_uri" => options.redirect_uri,
        "state" => options.state,
        "nonce" => options.nonce,
        "code_challenge" => options.code_challenge,
        "code_challenge_method" => "S256"
      })

    {:ok, "https://issuer.example.test/authorize?#{query}"}
  end

  def exchange_code(code, options) do
    send(test_pid(), {:oidc_exchange, code, options})

    Application.get_env(
      :quick_train,
      :oidc_test_exchange_result,
      {:ok,
       %{
         "iss" => "https://issuer.example.test",
         "sub" => "subject-1",
         "email" => "New.User@Example.test",
         "email_verified" => true,
         "name" => "  New User  "
       }}
    )
  end

  defp test_pid, do: Application.fetch_env!(:quick_train, :oidc_test_pid)
end

defmodule QuickTrain.OidcLoginTest do
  use QuickTrain.DataCase, async: false

  alias QuickTrain.Accounts

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
    result = Accounts.begin_oidc_login!("desktop", "198.51.100.10")

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

  test "begin rejects untrusted callback keys before persistence or provider work" do
    before_count = Ash.count!(QuickTrain.Accounts.OidcLoginTransaction, authorize?: false)

    assert {:error, error} = Accounts.begin_oidc_login("attacker", "198.51.100.11")
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

    _first = Accounts.begin_oidc_login!("desktop", "198.51.100.12")
    assert_receive {:oidc_authorization, _options}
    before_count = Ash.count!(QuickTrain.Accounts.OidcLoginTransaction, authorize?: false)

    assert {:error, error} = Accounts.begin_oidc_login("desktop", "198.51.100.12")
    assert Exception.message(error) =~ "rate_limited"

    assert Ash.count!(QuickTrain.Accounts.OidcLoginTransaction, authorize?: false) == before_count
    refute_receive {:oidc_authorization, _options}
  end

  test "exchange verifies the separate client proof before provider contact" do
    login = Accounts.begin_oidc_login!("desktop", "198.51.100.20")
    assert_receive {:oidc_authorization, _options}

    assert {:error, error} =
             Accounts.exchange_oidc_login("provider-code", login.state, "wrong-proof")

    assert Exception.message(error) =~ "invalid_oidc_exchange"
    refute_receive {:oidc_exchange, _code, _options}

    transaction = Accounts.get_oidc_login!(:crypto.hash(:sha256, login.state))
    assert transaction.status == "pending"
  end

  test "client callback handoff exchanges code and state into one bearer session" do
    login = Accounts.begin_oidc_login!("desktop", "198.51.100.21")
    assert_receive {:oidc_authorization, begin_options}

    result =
      Accounts.exchange_oidc_login!("provider-code", login.state, login.client_proof)

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

    login = Accounts.begin_oidc_login!("desktop", "198.51.100.22")
    assert_receive {:oidc_authorization, _options}

    assert {:error, first_error} =
             Accounts.exchange_oidc_login("invalid-code", login.state, login.client_proof)

    assert Exception.message(first_error) =~ "provider_exchange_failed"
    assert_receive {:oidc_exchange, "invalid-code", _options}

    transaction = Accounts.get_oidc_login!(:crypto.hash(:sha256, login.state))
    assert transaction.status == "exchanging"

    assert {:error, second_error} =
             Accounts.exchange_oidc_login("invalid-code", login.state, login.client_proof)

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

    login = Accounts.begin_oidc_login!("desktop", "198.51.100.23")
    assert_receive {:oidc_authorization, _options}

    result = Accounts.exchange_oidc_login!("provider-code", login.state, login.client_proof)

    assert result.user.id == user.id
    assert result.user.email == "original@example.test"
    assert Ash.count!(QuickTrain.Accounts.User, authorize?: false) == 1
  end

  test "a new subject cannot link to an existing account by email" do
    existing_user = Accounts.register_user!("new.user@example.test", "Existing")
    login = Accounts.begin_oidc_login!("desktop", "198.51.100.24")
    assert_receive {:oidc_authorization, _options}

    assert {:error, error} =
             Accounts.exchange_oidc_login("provider-code", login.state, login.client_proof)

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

    login = Accounts.begin_oidc_login!("desktop", "198.51.100.25")
    assert_receive {:oidc_authorization, _options}

    result = Accounts.exchange_oidc_login!("provider-code", login.state, login.client_proof)

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

    login = Accounts.begin_oidc_login!("desktop", "198.51.100.26")
    assert_receive {:oidc_authorization, _options}

    assert {:error, error} =
             Accounts.exchange_oidc_login("provider-code", login.state, login.client_proof)

    assert Exception.message(error) =~ "inactive_account"
    assert Ash.count!(QuickTrain.Accounts.Session, authorize?: false) == 0
    assert Accounts.get_user!(disabled_user.id).status == "disabled"
  end

  test "concurrent exchanges claim one transaction before contacting the provider" do
    login = Accounts.begin_oidc_login!("desktop", "198.51.100.27")
    assert_receive {:oidc_authorization, _options}

    results =
      1..2
      |> Enum.map(fn _attempt ->
        Task.async(fn ->
          Accounts.exchange_oidc_login("provider-code", login.state, login.client_proof)
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
    first_login = Accounts.begin_oidc_login!("desktop", "198.51.100.28")
    second_login = Accounts.begin_oidc_login!("desktop", "198.51.100.29")
    assert_receive {:oidc_authorization, _options}
    assert_receive {:oidc_authorization, _options}

    results =
      [first_login, second_login]
      |> Enum.map(fn login ->
        Task.async(fn ->
          Accounts.exchange_oidc_login("provider-code", login.state, login.client_proof)
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

  defp restore_env(key, nil), do: Application.delete_env(:quick_train, key)
  defp restore_env(key, value), do: Application.put_env(:quick_train, key, value)
end
