defmodule QuickTrain.EnterpriseIdentityTest do
  use QuickTrain.DataCase, async: true

  alias QuickTrain.{Accounts, EnterpriseIdentity, Organizations}

  test "directory deprovisioning removes enterprise access without deleting the user" do
    {:ok, user} = Accounts.register_user("employee@example.com", "Employee")
    {:ok, organization} = Organizations.create_organization("Enterprise", "enterprise")
    {:ok, membership} = Organizations.add_member(organization.id, user.id)

    {:ok, connection} =
      EnterpriseIdentity.create_connection(organization.id, "workos", "connection-123")

    {:ok, directory_user} =
      EnterpriseIdentity.link_directory_user(
        connection.id,
        membership.id,
        user.id,
        "directory-user-123"
      )

    assert :ok = EnterpriseIdentity.deprovision_directory_user(directory_user.id)
    assert {:ok, preserved_user} = Accounts.get_user(user.id)
    assert preserved_user.status == "active"
    refute Organizations.member?(organization.id, user.id)
    assert {:ok, _consumer_session} = Accounts.issue_session(user.id, %{})
  end
end
