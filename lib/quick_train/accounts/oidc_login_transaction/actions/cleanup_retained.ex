defmodule QuickTrain.Accounts.OidcLoginTransaction.Actions.CleanupRetained do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  require Ash.Query

  @impl true
  def run(input, _opts, _context) do
    now = input.arguments.now

    result =
      input.resource
      |> Ash.Query.filter(retain_until <= ^now and (expires_at <= ^now or status == "consumed"))
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
end
