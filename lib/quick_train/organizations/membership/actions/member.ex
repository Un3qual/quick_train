defmodule QuickTrain.Organizations.Membership.Actions.Member do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  require Ash.Query

  @impl true
  def run(input, _opts, _context) do
    input.resource
    |> Ash.Query.for_read(:read, %{}, authorize?: false)
    |> Ash.Query.filter(
      organization_id == ^input.arguments.organization_id and
        user_id == ^input.arguments.user_id and status == "active"
    )
    |> Ash.exists()
  end
end
