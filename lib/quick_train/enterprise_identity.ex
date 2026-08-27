defmodule QuickTrain.EnterpriseIdentity do
  @moduledoc "Provider-neutral enterprise SSO and directory synchronization boundaries."

  alias QuickTrain.EnterpriseIdentity.{EnterpriseConnection, DirectoryUser}
  alias QuickTrain.Organizations
  alias QuickTrain.Organizations.Membership

  def create_connection(organization_id, provider, external_id) do
    EnterpriseConnection
    |> Ash.Changeset.for_create(:create, %{
      organization_id: organization_id,
      provider: provider,
      external_id: external_id
    })
    |> Ash.create(authorize?: false)
  end

  def link_directory_user(connection_id, membership_id, user_id, external_id) do
    with {:ok, %EnterpriseConnection{organization_id: organization_id}} <-
           Ash.get(EnterpriseConnection, connection_id, authorize?: false),
         {:ok,
          %Membership{
            organization_id: ^organization_id,
            user_id: ^user_id,
            status: "active"
          }} <- Ash.get(Membership, membership_id, authorize?: false) do
      DirectoryUser
      |> Ash.Changeset.for_create(:link, %{
        connection_id: connection_id,
        membership_id: membership_id,
        user_id: user_id,
        external_id: external_id
      })
      |> Ash.create(authorize?: false)
    else
      _mismatched_scope -> {:error, :identity_scope_mismatch}
    end
  end

  def deprovision_directory_user(directory_user_id) do
    with {:ok, directory_user} <- Ash.get(DirectoryUser, directory_user_id, authorize?: false),
         {:ok, _directory_user} <-
           directory_user
           |> Ash.Changeset.for_update(:set_status, %{status: "inactive"})
           |> Ash.update(authorize?: false) do
      Organizations.deactivate_membership(directory_user.membership_id)
    end
  end
end
