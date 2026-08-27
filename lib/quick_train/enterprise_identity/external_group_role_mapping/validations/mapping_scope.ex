defmodule QuickTrain.EnterpriseIdentity.ExternalGroupRoleMapping.Validations.MappingScope do
  @moduledoc false

  use Ash.Resource.Validation

  alias QuickTrain.Authorization
  alias QuickTrain.Authorization.Role
  alias QuickTrain.EnterpriseIdentity

  alias QuickTrain.EnterpriseIdentity.{
    Directory,
    DirectoryGroup,
    EnterpriseConnection
  }

  @impl true
  def validate(changeset, _opts, _context) do
    directory_group_id = Ash.Changeset.get_attribute(changeset, :directory_group_id)
    role_id = Ash.Changeset.get_attribute(changeset, :role_id)

    with {:ok,
          %DirectoryGroup{
            directory: %Directory{
              enterprise_connection: %EnterpriseConnection{organization_id: organization_id}
            }
          }} <-
           EnterpriseIdentity.get_directory_group(directory_group_id,
             load: [directory: :enterprise_connection],
             authorize?: false
           ),
         {:ok, %Role{organization_id: ^organization_id}} <-
           Authorization.get_role(role_id, authorize?: false) do
      :ok
    else
      _mismatched_scope ->
        {:error, field: :role_id, message: "mapping scope mismatch"}
    end
  end
end
