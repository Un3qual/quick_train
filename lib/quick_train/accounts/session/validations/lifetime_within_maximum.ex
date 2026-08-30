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

    if within_maximum?(issued_at, expires_at, maximum_seconds) do
      :ok
    else
      {:error, field: :expires_at, message: "exceeds the configured session lifetime"}
    end
  end

  defp within_maximum?(%DateTime{} = issued_at, %DateTime{} = expires_at, maximum_seconds) do
    DateTime.compare(expires_at, DateTime.add(issued_at, maximum_seconds, :second)) != :gt
  end

  defp within_maximum?(_issued_at, _expires_at, _maximum_seconds), do: true
end
