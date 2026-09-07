defmodule QuickTrain.Datasets.ProductCapabilities.Actions.GrantToManager do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  require Ash.Query

  alias QuickTrain.Accounts.User
  alias QuickTrain.AshError
  alias QuickTrain.Authorization.{Capability, Role, RoleAssignment, RoleCapability}
  alias QuickTrain.Organizations.{Membership, Organization}

  @capabilities [
    {"assets.read", "Read organization assets"},
    {"assets.manage", "Register and finalize organization assets"},
    {"datasets.read", "Read organization datasets"},
    {"datasets.manage", "Manage organization datasets and schemas"},
    {"dataset_imports.manage", "Manage organization dataset imports"}
  ]
  @manager_key "manager"
  @attempts 2

  @impl true
  def run(input, _opts, _context) do
    grant(input.arguments.organization_id, input.arguments.user_id, @attempts)
  end

  defp grant(organization_id, user_id, attempts) do
    resources = [User, Organization, Membership, Role, RoleAssignment, Capability, RoleCapability]

    case Ash.transact(resources, fn ->
           grant_in_transaction(organization_id, user_id)
         end) do
      {:ok, keys} when is_list(keys) ->
        {:ok, keys}

      {:error, error} when attempts > 1 ->
        if uniqueness_conflict?(error) do
          grant(organization_id, user_id, attempts - 1)
        else
          {:error, :product_capability_grant_conflict}
        end

      {:error, _error} ->
        {:error, :product_capability_grant_conflict}

      _other ->
        {:error, :product_capability_grant_conflict}
    end
  end

  defp grant_in_transaction(organization_id, user_id) do
    with {:ok, _user} <- active_user(user_id),
         {:ok, _organization} <- active_organization(organization_id),
         {:ok, _membership} <- active_membership(organization_id, user_id),
         {:ok, role} <- manager_role(organization_id),
         {:ok, _assignment} <- manager_assignment(organization_id, user_id, role.id),
         {:ok, capabilities} <- capabilities(),
         :ok <- grant_capabilities(role.id, capabilities) do
      Enum.map(capabilities, & &1.key)
    end
  end

  defp active_organization(organization_id) do
    Organization
    |> Ash.Query.filter(id == ^organization_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> active_result()
  end

  defp active_user(user_id) do
    User
    |> Ash.Query.filter(id == ^user_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> active_result()
  end

  defp active_membership(organization_id, user_id) do
    Membership
    |> Ash.Query.filter(organization_id == ^organization_id and user_id == ^user_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> active_result()
  end

  defp active_result({:ok, %{status: "active"} = record}), do: {:ok, record}
  defp active_result(_result), do: {:error, :product_capability_grant_conflict}

  defp manager_role(organization_id) do
    case Role
         |> Ash.Query.filter(organization_id == ^organization_id and key == @manager_key)
         |> Ash.Query.lock(:for_update)
         |> Ash.read_one(authorize?: false) do
      {:ok, %{} = role} -> {:ok, role}
      _result -> {:error, :product_capability_grant_conflict}
    end
  end

  defp manager_assignment(organization_id, user_id, role_id) do
    case RoleAssignment
         |> Ash.Query.filter(
           organization_id == ^organization_id and user_id == ^user_id and role_id == ^role_id
         )
         |> Ash.Query.lock(:for_update)
         |> Ash.read_one(authorize?: false) do
      {:ok, %{} = assignment} -> {:ok, assignment}
      _result -> {:error, :product_capability_grant_conflict}
    end
  end

  defp capabilities do
    Enum.reduce_while(@capabilities, {:ok, []}, fn {key, description}, {:ok, capabilities} ->
      case capability(key, description) do
        {:ok, capability} -> {:cont, {:ok, [capability | capabilities]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> then(fn
      {:ok, capabilities} -> {:ok, Enum.reverse(capabilities)}
      error -> error
    end)
  end

  defp capability(key, description) do
    case Capability
         |> Ash.Query.filter(key == ^key)
         |> Ash.Query.lock(:for_update)
         |> Ash.read_one(authorize?: false) do
      {:ok, nil} ->
        Capability
        |> Ash.Changeset.for_create(:create, %{key: key, description: description})
        |> Ash.create(authorize?: false)

      {:ok, %{description: ^description} = capability} ->
        {:ok, capability}

      _result ->
        {:error, :product_capability_grant_conflict}
    end
  end

  defp grant_capabilities(role_id, capabilities) do
    Enum.reduce_while(capabilities, :ok, fn capability, :ok ->
      case grant_capability(role_id, capability.id) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp grant_capability(role_id, capability_id) do
    case RoleCapability
         |> Ash.Query.filter(role_id == ^role_id and capability_id == ^capability_id)
         |> Ash.Query.lock(:for_update)
         |> Ash.read_one(authorize?: false) do
      {:ok, nil} ->
        case RoleCapability
             |> Ash.Changeset.for_create(:grant, %{
               role_id: role_id,
               capability_id: capability_id
             })
             |> Ash.create(authorize?: false) do
          {:ok, _grant} -> :ok
          {:error, error} -> {:error, error}
        end

      {:ok, %RoleCapability{}} ->
        :ok

      {:error, error} ->
        {:error, error}
    end
  end

  defp uniqueness_conflict?(error) do
    AshError.constraint?(error, [
      "capabilities_key_index",
      "role_capabilities_role_capability_index"
    ])
  end
end
