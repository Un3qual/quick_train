defmodule QuickTrain.Forms.NestedRead do
  @moduledoc false
  use Ash.Policy.FilterCheck
  alias QuickTrain.Authorization.RoleAssignment

  @impl true
  def describe(_opts),
    do: "nested definitions belong to an organization the actor can inspect or manage"

  @impl true
  def filter(%{id: user_id, status: "active"}, _context, opts) do
    capabilities = Keyword.get(opts, :capabilities, ["forms.read", "forms.manage"])

    expr(
      exists(
        RoleAssignment,
        organization_id == parent(^ref(opts[:path], :organization_id)) and
          user_id == ^user_id and user.status == "active" and organization.status == "active" and
          exists(role.role_capabilities, capability.key in ^capabilities) and
          exists(organization.memberships, user_id == ^user_id and status == "active")
      )
    )
  end

  def filter(_actor, _context, _opts), do: false
end
