defmodule QuickTrain.Accounts.Oidc do
  @moduledoc "OIDC discovery, authorization-code redirects, and verified token exchange through oidcc."

  def authorization_url(options), do: provider().authorization_url(options)

  def exchange_code(code, options), do: provider().exchange_code(code, options)

  def nonce_for_verifier(pkce_verifier) do
    :crypto.mac(:hmac, :sha256, pkce_verifier, "quick-train-oidc-nonce-v1")
    |> Base.url_encode64(padding: false)
  end

  def issuer, do: config()[:issuer]

  def secure_callback_uri?(callback, allow_loopback_http?) when is_binary(callback) do
    case URI.parse(callback) do
      %URI{scheme: "https", host: host} when is_binary(host) and host != "" ->
        true

      %URI{scheme: "http", host: host} when allow_loopback_http? ->
        host in ["localhost", "127.0.0.1", "::1"]

      _uri ->
        false
    end
  end

  def secure_callback_uri?(_callback, _allow_loopback_http?), do: false

  def client_credentials do
    oidc_config = config()

    case {oidc_config[:client_id], oidc_config[:client_secret]} do
      {client_id, client_secret}
      when is_binary(client_id) and client_id != "" and is_binary(client_secret) and
             client_secret != "" ->
        {:ok, client_id, client_secret}

      _missing ->
        {:error, :oidc_not_configured}
    end
  end

  defp provider do
    :quick_train
    |> Application.get_env(:authentication, [])
    |> Keyword.get(:oidc_provider, QuickTrain.Accounts.OidccProvider)
  end

  defp config, do: Application.get_env(:quick_train, :human_oidc, [])
end
