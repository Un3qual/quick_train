defmodule QuickTrain.Accounts.Session.Actions.CleanupRetained do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  require Ash.Query

  alias QuickTrain.Accounts.Session

  @default_retention_seconds 86_400

  @impl true
  def run(input, _opts, _context) do
    cutoff = DateTime.add(input.arguments.now, -retention_seconds(), :second)

    result =
      Session
      |> Ash.Query.filter(expires_at <= ^cutoff and (is_nil(revoked_at) or revoked_at <= ^cutoff))
      |> Ash.bulk_destroy(:delete_retained, %{},
        authorize?: false,
        strategy: [:atomic],
        return_records?: true,
        return_errors?: true
      )

    case result do
      %Ash.BulkResult{status: :success, records: records} -> {:ok, length(records || [])}
      %Ash.BulkResult{errors: errors} -> {:error, Ash.Error.to_error_class(errors)}
    end
  end

  defp retention_seconds do
    :quick_train
    |> Application.get_env(:authentication, [])
    |> Keyword.get(:session_retention_seconds, @default_retention_seconds)
  end
end
