defmodule QuickTrain.Accounts.OidccProvider do
  @moduledoc false

  @behaviour QuickTrain.Accounts.OidcProvider

  alias Oidcc.{Authorization, ClientContext, ProviderConfiguration, Token}
  alias QuickTrain.Accounts.Oidc

  @impl true
  def authorization_url(options) do
    with {:ok, client_context} <- client_context(),
         {:ok, authorization_uri} <-
           Authorization.create_redirect_url(
             client_context,
             Map.drop(options, [:code_challenge])
           ),
         true <- secure_endpoint?(authorization_uri) do
      {:ok, authorization_uri}
    else
      false -> {:error, :insecure_provider_endpoint}
      {:error, error} -> {:error, error}
    end
  end

  @impl true
  def exchange_code(code, options) do
    with {:ok, client_context} <- client_context(),
         {:ok, token} <-
           Token.retrieve(code, client_context, options) do
      token_claims(token)
    else
      {:error, error} -> {:error, error}
    end
  end

  defp token_claims(token) do
    case Map.get(token, :id) do
      %{claims: claims} when is_map(claims) -> {:ok, claims}
      _missing_id_token -> {:error, :missing_id_token}
    end
  end

  def secure_provider_configuration?(%ProviderConfiguration{} = configuration) do
    required_endpoints = [
      configuration.issuer,
      configuration.authorization_endpoint,
      configuration.token_endpoint,
      configuration.jwks_uri
    ]

    optional_endpoints = [
      configuration.userinfo_endpoint,
      configuration.pushed_authorization_request_endpoint
    ]

    mtls_endpoints = Map.values(configuration.mtls_endpoint_aliases || %{})

    configuration.issuer == Oidc.issuer() and
      Enum.all?(required_endpoints, &secure_endpoint?/1) and
      Enum.all?(optional_endpoints, &secure_optional_endpoint?/1) and
      Enum.all?(mtls_endpoints, &secure_endpoint?/1)
  end

  def secure_provider_configuration?(_configuration), do: false

  defp client_context do
    with {:ok, client_id, client_secret} <- Oidc.client_credentials(),
         issuer when is_binary(issuer) <- Oidc.issuer(),
         true <- secure_endpoint?(issuer),
         {:ok, {configuration, _configuration_expiry}} <-
           ProviderConfiguration.load_configuration(issuer),
         true <- secure_provider_configuration?(configuration),
         {:ok, {jwks, _jwks_expiry}} <-
           ProviderConfiguration.load_jwks(configuration.jwks_uri) do
      {:ok, ClientContext.from_manual(configuration, jwks, client_id, client_secret)}
    else
      false -> {:error, :insecure_provider_endpoint}
      nil -> {:error, :oidc_not_configured}
      {:error, error} -> {:error, error}
    end
  end

  defp secure_optional_endpoint?(endpoint) when endpoint in [nil, :undefined], do: true
  defp secure_optional_endpoint?(endpoint), do: secure_endpoint?(endpoint)

  defp secure_endpoint?(endpoint) when is_binary(endpoint) do
    match?(
      %URI{scheme: "https", host: host} when is_binary(host) and host != "",
      URI.parse(endpoint)
    )
  end

  defp secure_endpoint?(_endpoint), do: false
end
