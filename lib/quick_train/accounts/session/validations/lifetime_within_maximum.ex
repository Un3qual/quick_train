defmodule QuickTrain.Accounts.Session.Validations.LifetimeWithinMaximum do
  @moduledoc false

  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    issued_at = Ash.Changeset.get_attribute(changeset, :issued_at)
    expires_at = Ash.Changeset.get_attribute(changeset, :expires_at)

    maximum_seconds =
      :quick_train
      |> Application.fetch_env!(:authentication)
      |> Keyword.fetch!(:session_max_lifetime_seconds)

    cond do
      future_issuance?(issued_at) ->
        {:error, field: :issued_at, message: "cannot be in the future"}

      not within_maximum?(issued_at, expires_at, maximum_seconds) ->
        {:error, field: :expires_at, message: "exceeds the configured session lifetime"}

      true ->
        :ok
    end
  end

  defp future_issuance?(%DateTime{} = issued_at) do
    DateTime.compare(issued_at, DateTime.utc_now()) == :gt
  end

  defp future_issuance?(_issued_at), do: false

  defp within_maximum?(%DateTime{} = issued_at, %DateTime{} = expires_at, maximum_seconds) do
    DateTime.compare(expires_at, DateTime.add(issued_at, maximum_seconds, :second)) != :gt
  end

  defp within_maximum?(_issued_at, _expires_at, _maximum_seconds), do: true
end
