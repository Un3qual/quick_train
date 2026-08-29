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
    {:error, :not_implemented}
  end

  defp test_pid, do: Application.fetch_env!(:quick_train, :oidc_test_pid)
end

defmodule QuickTrain.OidcLoginTest do
  use QuickTrain.DataCase, async: false

  alias QuickTrain.Accounts

  setup do
    original_authentication = Application.get_env(:quick_train, :authentication)
    original_test_pid = Application.get_env(:quick_train, :oidc_test_pid)

    limiter_namespace = "test-#{System.unique_integer([:positive])}"

    Application.put_env(:quick_train, :oidc_test_pid, self())

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

  defp restore_env(key, nil), do: Application.delete_env(:quick_train, key)
  defp restore_env(key, value), do: Application.put_env(:quick_train, key, value)
end
