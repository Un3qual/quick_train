defmodule QuickTrain.Authorization.RoleAssignment.Actions.Allowed do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias QuickTrain.Authorization.{Capability, RoleCapability}
  alias QuickTrain.Organizations

  require Ash.Query

  @impl true
  def run(input, _opts, _context) do
    %{user_id: user_id, organization_id: organization_id, capability_key: capability_key} =
      input.arguments

    allowed? =
      Organizations.member?(organization_id, user_id) and
        roles_allow?(input.resource, user_id, organization_id, capability_key)

    {:ok, allowed?}
  end

  defp roles_allow?(resource, user_id, organization_id, capability_key) do
    with {:ok, role_ids} <- role_ids(resource, user_id, organization_id),
         false <- Enum.empty?(role_ids),
         {:ok, capability_ids} <- capability_ids(capability_key),
         false <- Enum.empty?(capability_ids) do
      role_capability_exists?(role_ids, capability_ids)
    else
      _error_or_empty -> false
    end
  end

  defp role_ids(resource, user_id, organization_id) do
    resource
    |> Ash.Query.for_read(:read, %{}, authorize?: false)
    |> Ash.Query.filter(user_id == ^user_id and organization_id == ^organization_id)
    |> Ash.read()
    |> map_role_ids()
  end

  defp capability_ids(capability_key) do
    Capability
    |> Ash.Query.for_read(:read, %{}, authorize?: false)
    |> Ash.Query.filter(key == ^capability_key)
    |> Ash.read()
    |> map_ids()
  end

  defp role_capability_exists?(role_ids, capability_ids) do
    RoleCapability
    |> Ash.Query.for_read(:read, %{}, authorize?: false)
    |> Ash.Query.filter(role_id in ^role_ids and capability_id in ^capability_ids)
    |> Ash.exists()
    |> case do
      {:ok, exists?} -> exists?
      {:error, _error} -> false
    end
  end

  defp map_ids({:ok, records}), do: {:ok, Enum.map(records, & &1.id)}
  defp map_ids({:error, error}), do: {:error, error}

  defp map_role_ids({:ok, assignments}), do: {:ok, Enum.map(assignments, & &1.role_id)}
  defp map_role_ids({:error, error}), do: {:error, error}
end
