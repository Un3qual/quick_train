defmodule QuickTrain.Authentication.Error do
  @moduledoc false

  use Splode.Error, fields: [:operation, :category], class: :invalid

  require Logger

  @categories [
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

  def message(%{category: category}), do: Atom.to_string(category)

  def wrap(_operation, {:ok, _result} = result), do: result

  def wrap(operation, {:error, reason}) do
    category = failure_category(reason)

    Logger.warning("OIDC login failed",
      authentication_operation: operation,
      authentication_failure: category
    )

    {:error, exception(operation: operation, category: category)}
  end

  def public_message(:begin), do: "login unavailable"
  def public_message(:exchange), do: "login exchange failed"

  defp failure_category(reason) when reason in @categories, do: reason

  defp failure_category(reason) do
    message = reason_message(reason)

    Enum.find(@categories, :internal_error, fn category ->
      String.contains?(message, Atom.to_string(category))
    end)
  end

  defp reason_message(reason) when is_exception(reason), do: Exception.message(reason)
  defp reason_message(reason), do: inspect(reason)
end

defimpl AshGraphql.Error, for: QuickTrain.Authentication.Error do
  def to_error(error) do
    message = QuickTrain.Authentication.Error.public_message(error.operation)

    %{
      message: message,
      short_message: message,
      code: "authentication_failed",
      fields: [],
      vars: %{}
    }
  end
end
