defmodule QuickTrain.Accounts.Oidc do
  @moduledoc "OIDC discovery, authorization-code redirects, and verified token exchange through oidcc."

  @provider QuickTrain.Accounts.OidcProvider

  def children do
    case config()[:issuer] do
      issuer when is_binary(issuer) and issuer != "" ->
        [{Oidcc.ProviderConfiguration.Worker, %{issuer: issuer, name: @provider}}]

      _missing ->
        []
    end
  end

  def authorization_url(redirect_uri, opts \\ %{}) do
    with {:ok, client_id, client_secret} <- client_credentials() do
      Oidcc.create_redirect_url(
        @provider,
        client_id,
        client_secret,
        Map.merge(%{redirect_uri: redirect_uri}, opts)
      )
    end
  end

  def exchange_code(code, redirect_uri, opts \\ %{}) do
    with {:ok, client_id, client_secret} <- client_credentials() do
      Oidcc.retrieve_token(
        code,
        @provider,
        client_id,
        client_secret,
        Map.merge(%{redirect_uri: redirect_uri}, opts)
      )
    end
  end

  defp client_credentials do
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

  defp config, do: Application.get_env(:quick_train, :human_oidc, [])
end
