defmodule QuickTrainWeb.GraphQL.AuthenticationResolver do
  @moduledoc false

  alias QuickTrain.Accounts

  def begin_oidc_login(_parent, %{callback_key: callback_key}, resolution) do
    network_source = Map.get(resolution.context, :authentication_network_source, "unknown")

    case Accounts.begin_oidc_login(callback_key, network_source, authorize?: false) do
      {:ok, result} ->
        {:ok,
         %{
           authorization_uri: result.authorization_uri,
           state: result.state,
           client_proof: result.client_proof,
           expires_at: DateTime.to_iso8601(result.expires_at)
         }}

      {:error, _error} ->
        {:error, "login unavailable"}
    end
  end

  def exchange_oidc_login(
        _parent,
        %{code: code, state: state, client_proof: client_proof},
        _resolution
      ) do
    case Accounts.exchange_oidc_login(code, state, client_proof, authorize?: false) do
      {:ok, result} ->
        {:ok,
         %{
           token: result.token,
           session_id: result.session_id,
           expires_at: DateTime.to_iso8601(result.expires_at)
         }}

      {:error, _error} ->
        {:error, "login exchange failed"}
    end
  end
end
