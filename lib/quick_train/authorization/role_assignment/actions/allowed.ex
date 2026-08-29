defmodule QuickTrain.Authorization.RoleAssignment.Actions.Allowed do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  require Ash.Query

  @impl true
  def run(input, _opts, _context) do
    %{user_id: user_id, organization_id: organization_id, capability_key: capability_key} =
      input.arguments

    input.resource
    |> Ash.Query.filter(
      user_id == ^user_id and organization_id == ^organization_id and
        user.status == "active" and organization.status == "active" and
        exists(role.role_capabilities, capability.key == ^capability_key) and
        exists(
          organization.memberships,
          user_id == parent(user_id) and status == "active"
        )
    )
    |> Ash.exists(authorize?: false)
  end
end
