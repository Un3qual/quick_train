defmodule QuickTrain.Authorization do
  @moduledoc "Fail-closed, organization-scoped role and capability checks."

  alias QuickTrain.Authorization.{Capability, RoleAssignment, RoleCapability}
  alias QuickTrain.Organizations
  require Ash.Query

  # def create_role(organization_id, key, name) do
  #   Role
  #   |> Ash.Changeset.for_create(:create, %{organization_id: organization_id, key: key, name: name})
  #   |> Ash.create(authorize?: false)
  # end

  # def create_capability(key, description) do
  #   Capability
  #   |> Ash.Changeset.for_create(:create, %{key: key, description: description})
  #   |> Ash.create(authorize?: false)
  # end

  # def grant_capability(role_id, capability_id) do
  #   RoleCapability
  #   |> Ash.Changeset.for_create(:grant, %{role_id: role_id, capability_id: capability_id})
  #   |> Ash.create(authorize?: false)
  #   |> ok()
  # end

  # def assign_role(organization_id, user_id, role_id) do
  #   cond do
  #     not Organizations.member?(organization_id, user_id) ->
  #       {:error, :membership_required}

  #     not role_in_organization?(role_id, organization_id) ->
  #       {:error, :role_scope_mismatch}

  #     true ->
  #       RoleAssignment
  #       |> Ash.Changeset.for_create(:assign, %{
  #         organization_id: organization_id,
  #         user_id: user_id,
  #         role_id: role_id
  #       })
  #       |> Ash.create(authorize?: false)
  #       |> ok()
  #   end
  # end

  def allowed?(user_id, organization_id, capability_key) do
    Organizations.member?(organization_id, user_id) and
      role_ids(user_id, organization_id)
      |> roles_allow?(capability_key)
  end

  defp role_ids(user_id, organization_id) do
    RoleAssignment
    |> Ash.Query.filter(user_id == ^user_id and organization_id == ^organization_id)
    |> assignment_role_ids()
  end

  defp roles_allow?([], _capability_key), do: false

  defp roles_allow?(role_ids, capability_key) do
    capability_ids =
      Capability
      |> Ash.Query.filter(key == ^capability_key)
      |> Ash.read(authorize?: false)
      |> case do
        {:ok, capabilities} -> Enum.map(capabilities, & &1.id)
        {:error, _error} -> []
      end

    RoleCapability
    |> Ash.Query.filter(role_id in ^role_ids and capability_id in ^capability_ids)
    |> Ash.exists?(authorize?: false)
  end

  defp assignment_role_ids(query) do
    case Ash.read(query, authorize?: false) do
      {:ok, assignments} -> Enum.map(assignments, & &1.role_id)
      {:error, _error} -> []
    end
  end
end
