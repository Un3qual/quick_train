defmodule QuickTrain.EnterpriseIdentity.ExternalGroupRoleMapping.Validations.MappingScope do
  @moduledoc false

  use Ash.Resource.Validation

  alias QuickTrain.Authorization.Role

  alias QuickTrain.EnterpriseIdentity.{
    Directory,
    DirectoryGroup,
    EnterpriseConnection
  }

  require Ash.Query

  @impl true
  def validate(changeset, _opts, _context) do
    with {:ok, scopes} <- load_scopes([changeset]),
         true <- valid_scope?(changeset, scopes) do
      :ok
    else
      _mismatched_scope ->
        {:error, scope_error()}
    end
  end

  @impl true
  def batch_validate(changesets, _opts, _context) do
    case load_scopes(changesets) do
      {:ok, scopes} ->
        Enum.map(changesets, fn changeset ->
          if valid_scope?(changeset, scopes) do
            changeset
          else
            Ash.Changeset.add_error(changeset, scope_error())
          end
        end)

      {:error, error} ->
        Enum.map(changesets, &Ash.Changeset.add_error(&1, error))
    end
  end

  defp load_scopes(changesets) do
    directory_group_ids = attribute_values(changesets, :directory_group_id)
    role_ids = attribute_values(changesets, :role_id)

    with {:ok, directory_groups} <- read_directory_groups(directory_group_ids),
         {:ok, roles} <- read_by_ids(Role, role_ids) do
      {:ok,
       %{
         directory_groups: Map.new(directory_groups, &directory_group_scope/1),
         roles: Map.new(roles, &{&1.id, &1.organization_id})
       }}
    end
  end

  defp read_directory_groups(ids) do
    DirectoryGroup
    |> Ash.Query.filter(id in ^ids)
    |> Ash.Query.load(directory: :enterprise_connection)
    |> Ash.read(authorize?: false)
  end

  defp read_by_ids(resource, ids) do
    resource
    |> Ash.Query.filter(id in ^ids)
    |> Ash.read(authorize?: false)
  end

  defp attribute_values(changesets, attribute) do
    changesets
    |> Enum.map(&Ash.Changeset.get_attribute(&1, attribute))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp directory_group_scope(%DirectoryGroup{
         id: id,
         directory: %Directory{
           enterprise_connection: %EnterpriseConnection{organization_id: organization_id}
         }
       }) do
    {id, organization_id}
  end

  defp directory_group_scope(%DirectoryGroup{id: id}), do: {id, nil}

  defp valid_scope?(changeset, scopes) do
    directory_group_id = Ash.Changeset.get_attribute(changeset, :directory_group_id)
    role_id = Ash.Changeset.get_attribute(changeset, :role_id)

    organization_id = Map.get(scopes.directory_groups, directory_group_id)

    not is_nil(organization_id) and Map.get(scopes.roles, role_id) == organization_id
  end

  defp scope_error do
    [field: :role_id, message: "mapping scope mismatch"]
  end
end
