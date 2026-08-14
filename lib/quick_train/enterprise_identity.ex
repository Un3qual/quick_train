defmodule QuickTrain.EnterpriseIdentity do
  @moduledoc "Provider-neutral enterprise SSO and directory synchronization boundaries."

  alias QuickTrain.EnterpriseIdentity.{Connection, DirectoryUser}
  alias QuickTrain.Organizations

  def create_connection(organization_id, provider, external_id) do
    Connection
    |> Ash.Changeset.for_create(:create, %{
      organization_id: organization_id,
      provider: provider,
      external_id: external_id
    })
    |> Ash.create(authorize?: false)
  end

  def link_directory_user(connection_id, membership_id, user_id, external_id) do
    DirectoryUser
    |> Ash.Changeset.for_create(:link, %{
      connection_id: connection_id,
      membership_id: membership_id,
      user_id: user_id,
      external_id: external_id
    })
    |> Ash.create(authorize?: false)
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
