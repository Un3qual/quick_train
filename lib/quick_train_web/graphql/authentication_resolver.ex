defmodule QuickTrainWeb.GraphQL.AuthenticationResolver do
  @moduledoc false

  require Logger

  alias QuickTrain.Accounts

  @failure_categories [
    :untrusted_callback,
    :rate_limited,
    :outstanding_limit,
    :outstanding_admission_unavailable,
    :provider_unavailable,
    :state_collision,
    :invalid_network_source,
    :invalid_oidc_exchange,
    :provider_exchange_failed,
    :invalid_provider_identity,
    :inactive_account,
    :identity_conflict,
    :verified_email_required,
    :account_linking_conflict
  ]

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

      {:error, error} ->
        log_failure(:begin, error)
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

      {:error, error} ->
        log_failure(:exchange, error)
        {:error, "login exchange failed"}
    end
  end

  defp log_failure(operation, error) do
    Logger.warning("OIDC login failed",
      authentication_operation: operation,
      authentication_failure: failure_category(error)
    )
  end

  defp failure_category(error) do
    message = Exception.message(error)

    Enum.find(@failure_categories, :internal_error, fn category ->
      String.contains?(message, Atom.to_string(category))
    end)
  end
end
