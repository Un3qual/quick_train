defmodule QuickTrain.Accounts.User.Actions.BootstrapFirstManager do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  require Ash.Query

  alias QuickTrain.Authorization.{Role, RoleAssignment}
  alias QuickTrain.Organizations.{Membership, Organization}

  @manager_key "manager"
  @manager_name "Manager"
  @attempts 2

  @impl true
  def run(input, _opts, _context) do
    user_id = input.arguments.user_id
    slug = input.arguments.organization_slug |> String.trim() |> String.downcase()
    name = String.trim(input.arguments.organization_name)

    if valid_slug?(slug) and name != "" do
      bootstrap(input.resource, user_id, slug, name, @attempts)
    else
      {:error, :bootstrap_conflict}
    end
  end

  defp bootstrap(user_resource, user_id, slug, name, attempts) do
    resources = [user_resource, Organization, Membership, Role, RoleAssignment]

    case Ash.transact(resources, fn ->
           bootstrap_in_transaction(user_resource, user_id, slug, name)
         end) do
      {:ok, graph} ->
        {:ok, graph}

      {:error, error} when attempts > 1 ->
        if uniqueness_conflict?(error) do
          bootstrap(user_resource, user_id, slug, name, attempts - 1)
        else
          {:error, :bootstrap_conflict}
        end

      {:error, _error} ->
        {:error, :bootstrap_conflict}
    end
  end

  defp bootstrap_in_transaction(user_resource, user_id, slug, name) do
    with {:ok, user} <- active_user(user_resource, user_id),
         {:ok, organization} <- organization(slug, name),
         {:ok, membership} <- membership(organization.id, user.id),
         {:ok, role} <- manager_role(organization.id),
         {:ok, assignment} <- manager_assignment(organization.id, user.id, role.id) do
      %{
        user: user,
        organization: organization,
        membership: membership,
        role: role,
        assignment: assignment
      }
    end
  end

  defp active_user(resource, user_id) do
    user =
      resource
      |> Ash.Query.filter(id == ^user_id)
      |> Ash.Query.lock(:for_update)
      |> Ash.read_one!(authorize?: false)

    case user do
      %{status: "active"} -> {:ok, user}
      _user -> {:error, :bootstrap_conflict}
    end
  end

  defp organization(slug, name) do
    existing =
      Organization
      |> Ash.Query.filter(slug == ^slug)
      |> Ash.Query.lock(:for_update)
      |> Ash.read_one!(authorize?: false)

    case existing do
      nil ->
        create(Organization, :bootstrap_first_manager_organization, %{name: name, slug: slug})

      %{status: "active", name: ^name} = organization ->
        {:ok, organization}

      %{} ->
        {:error, :bootstrap_conflict}
    end
  end

  defp membership(organization_id, user_id) do
    existing =
      Membership
      |> Ash.Query.filter(organization_id == ^organization_id and user_id == ^user_id)
      |> Ash.Query.lock(:for_update)
      |> Ash.read_one!(authorize?: false)

    case existing do
      nil ->
        create(Membership, :bootstrap_first_manager_membership, %{
          organization_id: organization_id,
          user_id: user_id
        })

      %{status: "active"} = membership ->
        {:ok, membership}

      %{} ->
        {:error, :bootstrap_conflict}
    end
  end

  defp manager_role(organization_id) do
    existing =
      Role
      |> Ash.Query.filter(organization_id == ^organization_id and key == @manager_key)
      |> Ash.Query.lock(:for_update)
      |> Ash.read_one!(authorize?: false)

    case existing do
      nil ->
        create(Role, :bootstrap_first_manager_role, %{organization_id: organization_id})

      %{name: @manager_name} = role ->
        {:ok, role}

      %{} ->
        {:error, :bootstrap_conflict}
    end
  end

  defp manager_assignment(organization_id, user_id, role_id) do
    assignments =
      RoleAssignment
      |> Ash.Query.filter(organization_id == ^organization_id and role_id == ^role_id)
      |> Ash.Query.lock(:for_update)
      |> Ash.read!(authorize?: false)

    case assignments do
      [] ->
        create(RoleAssignment, :bootstrap_first_manager_assignment, %{
          organization_id: organization_id,
          user_id: user_id,
          role_id: role_id
        })

      [%{user_id: ^user_id} = assignment] ->
        {:ok, assignment}

      _conflict ->
        {:error, :bootstrap_conflict}
    end
  end

  defp uniqueness_conflict?(error) do
    message = Exception.message(error)

    String.contains?(message, "has already been taken") or
      Enum.any?(
        [
          "organizations_slug_index",
          "organization_memberships_organization_user_index",
          "roles_organization_key_index",
          "role_assignments_organization_user_role_index"
        ],
        &String.contains?(message, &1)
      )
  end

  defp create(resource, action, attributes) do
    resource
    |> Ash.Changeset.for_create(action, attributes)
    |> Ash.create(authorize?: false)
  end

  defp valid_slug?(slug), do: Regex.match?(~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/, slug)
end
