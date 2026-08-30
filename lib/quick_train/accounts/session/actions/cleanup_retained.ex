defmodule QuickTrain.Accounts.Session.Actions.CleanupRetained do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  require Ash.Query

  @impl true
  def run(input, _opts, _context) do
    cutoff = DateTime.add(input.arguments.now, -retention_seconds(), :second)

    result =
      input.resource
      |> Ash.Query.filter(expires_at <= ^cutoff and (is_nil(revoked_at) or revoked_at <= ^cutoff))
      |> Ash.bulk_destroy(:delete_retained, %{},
        authorize?: false,
        strategy: [:atomic],
        return_errors?: true
      )

    case result do
      %Ash.BulkResult{status: :success} -> {:ok, true}
      %Ash.BulkResult{errors: errors} -> {:error, Ash.Error.to_error_class(errors)}
    end
  end

  defp retention_seconds do
    :quick_train
    |> Application.fetch_env!(:authentication)
    |> Keyword.fetch!(:session_retention_seconds)
  end
end
