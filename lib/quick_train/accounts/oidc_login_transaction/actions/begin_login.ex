defmodule QuickTrain.Accounts.OidcLoginTransaction.Actions.BeginLogin do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  require Ash.Query

  alias QuickTrain.Accounts.Oidc
  alias QuickTrain.Accounts.OidcBeginLimiter

  @state_bytes 32
  @proof_bytes 32
  @verifier_bytes 64
  @default_window_ms 60_000
  @default_global_limit 300
  @default_network_limit 20
  @default_outstanding_limit 10_000
  @default_transaction_ttl_seconds 300
  @default_replay_retention_seconds 86_400
  @collision_attempts 3
  @allow_loopback_http Mix.env() in [:dev, :test]

  @impl true
  def run(input, _opts, _context) do
    resource = input.resource
    callback_key = input.arguments.callback_key
    network_source = input.arguments.network_source

    with {:ok, callback_uri} <- trusted_callback(callback_key),
         :ok <- admit(resource, network_source),
         {:ok, transaction, material} <-
           persist_fresh_transaction(resource, callback_key, callback_uri),
         {:ok, authorization_uri} <-
           provider_authorization_url(transaction, material, callback_uri) do
      {:ok,
       %{
         authorization_uri: authorization_uri,
         state: material.state,
         client_proof: material.client_proof,
         expires_at: transaction.expires_at
       }}
    else
      {:provider_error, transaction} ->
        _result = Ash.destroy(transaction, action: :discard, authorize?: false)
        {:error, :provider_unavailable}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp trusted_callback(callback_key) do
    callback_key = to_string(callback_key)

    callback =
      config()
      |> Keyword.get(:oidc_callbacks, [])
      |> Enum.find_value(fn {key, uri} ->
        if to_string(key) == callback_key, do: uri
      end)

    if Oidc.secure_callback_uri?(callback, @allow_loopback_http),
      do: {:ok, callback},
      else: {:error, :untrusted_callback}
  end

  defp admit(resource, network_source) when is_binary(network_source) and network_source != "" do
    settings = config()
    namespace = Keyword.get(settings, :oidc_begin_limiter_namespace, "oidc-begin")
    window_ms = Keyword.get(settings, :oidc_begin_window_ms, @default_window_ms)
    global_limit = Keyword.get(settings, :oidc_begin_global_limit, @default_global_limit)
    network_limit = Keyword.get(settings, :oidc_begin_network_limit, @default_network_limit)

    with {:allow, _count} <-
           OidcBeginLimiter.hit({namespace, :global}, window_ms, global_limit),
         {:allow, _count} <-
           OidcBeginLimiter.hit({namespace, :network, network_source}, window_ms, network_limit),
         :ok <- admit_outstanding(resource, settings) do
      :ok
    else
      {:deny, _retry_after} -> {:error, :rate_limited}
      {:error, reason} -> {:error, reason}
    end
  end

  defp admit(_resource, _network_source), do: {:error, :invalid_network_source}

  defp admit_outstanding(resource, settings) do
    now = DateTime.utc_now()
    limit = Keyword.get(settings, :oidc_outstanding_limit, @default_outstanding_limit)

    count =
      resource
      |> Ash.Query.filter(status in ["pending", "exchanging"] and expires_at > ^now)
      |> Ash.count!(authorize?: false)

    if count < limit, do: :ok, else: {:error, :outstanding_limit}
  end

  defp persist_fresh_transaction(
         resource,
         callback_key,
         callback_uri,
         attempts \\ @collision_attempts
       )

  defp persist_fresh_transaction(_resource, _callback_key, _callback_uri, 0),
    do: {:error, :state_collision}

  defp persist_fresh_transaction(resource, callback_key, callback_uri, attempts) do
    material = generate_material()
    state_hash = sha256(material.state)
    now = DateTime.utc_now()
    settings = config()

    expires_at =
      DateTime.add(
        now,
        Keyword.get(settings, :oidc_transaction_ttl_seconds, @default_transaction_ttl_seconds),
        :second
      )

    retain_until =
      DateTime.add(
        expires_at,
        Keyword.get(
          settings,
          :oidc_replay_retention_seconds,
          @default_replay_retention_seconds
        ),
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

    case resource
         |> Ash.Query.filter(state_hash == ^state_hash)
         |> Ash.read_one(authorize?: false) do
      {:ok, nil} ->
        create_transaction(
          resource,
          attributes,
          material,
          callback_key,
          callback_uri,
          attempts
        )

      {:ok, _collision} ->
        persist_fresh_transaction(resource, callback_key, callback_uri, attempts - 1)

      {:error, error} ->
        {:error, error}
    end
  end

  defp create_transaction(
         resource,
         attributes,
         material,
         callback_key,
         callback_uri,
         attempts
       ) do
    result =
      resource
      |> Ash.Changeset.for_create(:begin, attributes)
      |> Ash.create(authorize?: false)

    case result do
      {:ok, transaction} ->
        {:ok, transaction, material}

      {:error, error} ->
        if state_collision?(error) do
          persist_fresh_transaction(resource, callback_key, callback_uri, attempts - 1)
        else
          {:error, error}
        end
    end
  end

  defp state_collision?(error) do
    error
    |> Exception.message()
    |> String.contains?("oidc_login_transactions_state_hash_index")
  end

  defp generate_material do
    state = random_url_value(@state_bytes)
    client_proof = random_url_value(@proof_bytes)
    pkce_verifier = random_url_value(@verifier_bytes)

    nonce = Oidc.nonce_for_verifier(pkce_verifier)

    code_challenge = pkce_verifier |> sha256() |> Base.url_encode64(padding: false)

    %{
      state: state,
      nonce: nonce,
      client_proof: client_proof,
      pkce_verifier: pkce_verifier,
      code_challenge: code_challenge
    }
  end

  defp provider_authorization_url(transaction, material, callback_uri) do
    options = %{
      redirect_uri: callback_uri,
      state: material.state,
      nonce: material.nonce,
      pkce_verifier: material.pkce_verifier,
      code_challenge: material.code_challenge,
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
  defp config, do: Application.get_env(:quick_train, :authentication, [])
end
