defmodule QuickTrain.Accounts.Workers.AuthenticationRetention do
  @moduledoc false

  use Oban.Worker,
    queue: :authentication,
    max_attempts: 5,
    unique: [
      period: :infinity,
      fields: [:worker],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias QuickTrain.Accounts

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    now = DateTime.utc_now()

    results = [
      Accounts.cleanup_retained_oidc_logins(now, authorize?: false),
      Accounts.cleanup_retained_sessions(now, authorize?: false)
    ]

    case Enum.reject(results, &match?({:ok, _count}, &1)) do
      [] -> :ok
      errors -> {:error, {:authentication_retention_failed, length(errors)}}
    end
  end
end
