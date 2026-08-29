defmodule QuickTrain.Accounts.Session.Actions.IssueBearer do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias QuickTrain.Accounts

  @token_bytes 32
  @default_max_lifetime_seconds 8 * 60 * 60

  @impl true
  def run(input, _opts, _context) do
    issued_at = DateTime.utc_now()
    lifetime_seconds = bounded_lifetime(input.arguments[:lifetime_seconds])
    token = @token_bytes |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

    attributes = %{
      user_id: input.arguments.user_id,
      token_hash: :crypto.hash(:sha256, token),
      authentication_method: "oidc",
      issued_at: issued_at,
      expires_at: DateTime.add(issued_at, lifetime_seconds, :second)
    }

    case Accounts.persist_bearer_session(attributes, authorize?: false) do
      {:ok, session} ->
        {:ok, %{token: token, session_id: session.id, expires_at: session.expires_at}}

      {:error, error} ->
        {:error, error}
    end
  end

  defp bounded_lifetime(requested_seconds) do
    maximum_seconds =
      :quick_train
      |> Application.get_env(:authentication, [])
      |> Keyword.get(:session_max_lifetime_seconds, @default_max_lifetime_seconds)

    requested_seconds
    |> Kernel.||(maximum_seconds)
    |> max(1)
    |> min(maximum_seconds)
  end
end
