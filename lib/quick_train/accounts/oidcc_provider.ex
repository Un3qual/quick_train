defmodule QuickTrain.Accounts.OidccProvider do
  @moduledoc false

  @behaviour QuickTrain.Accounts.OidcProvider

  alias QuickTrain.Accounts.Oidc

  @impl true
  def authorization_url(options) do
    with {:ok, client_id, client_secret} <- Oidc.client_credentials() do
      options = Map.drop(options, [:code_challenge])

      Oidcc.create_redirect_url(
        Oidc.provider_name(),
        client_id,
        client_secret,
        options
      )
    end
  end

  @impl true
  def exchange_code(code, options) do
    with {:ok, client_id, client_secret} <- Oidc.client_credentials(),
         {:ok, %Oidcc.Token{id: %Oidcc.Token.Id{claims: claims}}} <-
           Oidcc.retrieve_token(
             code,
             Oidc.provider_name(),
             client_id,
             client_secret,
             options
           ) do
      {:ok, claims}
    else
      {:ok, %Oidcc.Token{}} -> {:error, :missing_id_token}
      {:error, error} -> {:error, error}
    end
  end
end
