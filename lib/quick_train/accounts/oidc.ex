defmodule QuickTrain.Accounts.Oidc do
  @moduledoc "OIDC discovery, authorization-code redirects, and verified token exchange through oidcc."

  @provider QuickTrain.Accounts.OidcProvider

  def provider_name, do: @provider

  def children do
    case config()[:issuer] do
      issuer when is_binary(issuer) and issuer != "" ->
        [{Oidcc.ProviderConfiguration.Worker, %{issuer: issuer, name: @provider}}]

      _missing ->
        []
    end
  end

  def authorization_url(options), do: provider().authorization_url(options)

  def exchange_code(code, options), do: provider().exchange_code(code, options)

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
