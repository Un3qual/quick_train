defmodule QuickTrain.Authentication.Api.Actions.BeginOidcLogin do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  require Ash.Query

  alias QuickTrain.Accounts
  alias QuickTrain.Accounts.{Oidc, OidcBeginLimiter, OidcLoginTransaction}
  alias QuickTrain.AshError
  alias QuickTrain.Authentication.{Error, OidcBeginResult}

  @state_bytes 32
  @proof_bytes 32
  @verifier_bytes 64
  @collision_attempts 3
  @outstanding_admission_lock {__MODULE__, :outstanding_state_admission}
  @allow_loopback_http Mix.env() in [:dev, :test]

  @impl true
  def run(input, _opts, _context) do
    Error.wrap(:begin, begin_login(input))
  end

  defp begin_login(input) do
    callback_key = input.arguments.callback_key
    network_source = Map.get(input.context, :authentication_network_source)

    with {:ok, callback_uri} <- trusted_callback(callback_key),
         :ok <- admit(network_source),
         {:ok, transaction, material} <-
           persist_admitted_transaction(callback_key, callback_uri),
         {:ok, authorization_uri} <-
           provider_authorization_url(transaction, material, callback_uri) do
      {:ok,
       %OidcBeginResult{
         authorization_uri: authorization_uri,
         state: material.state,
         client_proof: material.client_proof,
         expires_at: transaction.expires_at
       }}
    else
      {:provider_error, transaction} ->
        _result = Accounts.discard_oidc_login(transaction, authorize?: false)
        {:error, :provider_unavailable}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp trusted_callback(callback_key) do
    callback_key = to_string(callback_key)

    callback =
      config()
      |> Keyword.fetch!(:oidc_callbacks)
      |> Enum.find_value(fn {key, uri} ->
        if to_string(key) == callback_key, do: uri
      end)

    if Oidc.secure_callback_uri?(callback, @allow_loopback_http),
      do: {:ok, callback},
      else: {:error, :untrusted_callback}
  end

  defp admit(network_source) when is_binary(network_source) and network_source != "" do
    settings = config()
    namespace = Keyword.get(settings, :oidc_begin_limiter_namespace, "oidc-begin")
    window_ms = Keyword.fetch!(settings, :oidc_begin_window_ms)
    global_limit = Keyword.fetch!(settings, :oidc_begin_global_limit)
    network_limit = Keyword.fetch!(settings, :oidc_begin_network_limit)

    with {:allow, _count} <-
           OidcBeginLimiter.hit({namespace, :global}, window_ms, global_limit),
         {:allow, _count} <-
           OidcBeginLimiter.hit({namespace, :network, network_source}, window_ms, network_limit) do
      :ok
    else
      {:deny, _retry_after} -> {:error, :rate_limited}
    end
  end

  defp admit(_network_source), do: {:error, :invalid_network_source}

  defp persist_admitted_transaction(callback_key, callback_uri) do
    lock_id = {@outstanding_admission_lock, self()}

    case :global.trans(lock_id, fn ->
           admit_and_persist(callback_key, callback_uri)
         end) do
      :aborted -> {:error, :outstanding_admission_unavailable}
      result -> result
    end
  end

  defp admit_and_persist(callback_key, callback_uri) do
    with :ok <- admit_outstanding(config()) do
      persist_fresh_transaction(callback_key, callback_uri)
    end
  end

  defp admit_outstanding(settings) do
    now = DateTime.utc_now()
    limit = Keyword.fetch!(settings, :oidc_outstanding_limit)

    count =
      OidcLoginTransaction
      |> Ash.Query.filter(status in ["pending", "exchanging"] and expires_at > ^now)
      |> Ash.count!(authorize?: false)

    if count < limit, do: :ok, else: {:error, :outstanding_limit}
  end

  defp persist_fresh_transaction(
         callback_key,
         callback_uri,
         attempts \\ @collision_attempts
       )

  defp persist_fresh_transaction(_callback_key, _callback_uri, 0),
    do: {:error, :state_collision}

  defp persist_fresh_transaction(callback_key, callback_uri, attempts) do
    material = generate_material()
    state_hash = sha256(material.state)
    now = DateTime.utc_now()
    settings = config()

    expires_at =
      DateTime.add(
        now,
        Keyword.fetch!(settings, :oidc_transaction_ttl_seconds),
        :second
      )

    retain_until =
      DateTime.add(
        expires_at,
        Keyword.fetch!(settings, :oidc_replay_retention_seconds),
        :second
      )

    attributes = %{
      state_hash: state_hash,
      nonce_hash: sha256(material.nonce),
      code_verifier: material.pkce_verifier,
      redemption_secret_hash: sha256(material.client_proof),
      callback_key: to_string(callback_key),
      callback_uri: callback_uri,
      expires_at: expires_at,
      retain_until: retain_until
    }

    create_transaction(attributes, material, callback_key, callback_uri, attempts)
  end

  defp create_transaction(
         attributes,
         material,
         callback_key,
         callback_uri,
         attempts
       ) do
    result = Accounts.store_oidc_login(attributes, authorize?: false)

    case result do
      {:ok, transaction} ->
        {:ok, transaction, material}

      {:error, error} ->
        if state_collision?(error) do
          persist_fresh_transaction(callback_key, callback_uri, attempts - 1)
        else
          {:error, error}
        end
    end
  end

  defp state_collision?(error) do
    AshError.constraint?(error, ["oidc_login_transactions_state_hash_index"])
  end

  defp generate_material do
    state = random_url_value(@state_bytes)
    client_proof = random_url_value(@proof_bytes)
    pkce_verifier = random_url_value(@verifier_bytes)

    nonce = Oidc.nonce_for_verifier(pkce_verifier)

    %{
      state: state,
      nonce: nonce,
      client_proof: client_proof,
      pkce_verifier: pkce_verifier
    }
  end

  defp provider_authorization_url(transaction, material, callback_uri) do
    options = %{
      redirect_uri: callback_uri,
      state: material.state,
      nonce: material.nonce,
      pkce_verifier: material.pkce_verifier,
      require_pkce: true,
      scopes: ["openid", "email", "profile"]
    }

    case Oidc.authorization_url(options) do
      {:ok, authorization_uri} -> {:ok, authorization_uri}
      {:error, _reason} -> {:provider_error, transaction}
    end
  end

  defp random_url_value(bytes) do
    bytes |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end

  defp sha256(value), do: :crypto.hash(:sha256, value)
  defp config, do: Application.fetch_env!(:quick_train, :authentication)
end
