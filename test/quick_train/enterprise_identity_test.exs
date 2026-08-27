defmodule QuickTrain.EnterpriseIdentityTest do
  use QuickTrain.DataCase, async: true

  alias QuickTrain.{Accounts, Authorization, EnterpriseIdentity, Organizations}

  test "directory deprovisioning removes enterprise access without deleting the user" do
    {:ok, user} = Accounts.register_user("employee@example.com", "Employee")
    {:ok, organization} = Organizations.create_organization("Enterprise", "enterprise")
    {:ok, membership} = Organizations.add_member(organization.id, user.id)

    {:ok, connection} =
      EnterpriseIdentity.create_connection(organization.id, "workos", "connection-123")

    assert {:ok, persisted_connection} =
             EnterpriseIdentity.get_enterprise_connection(connection.id)

    assert persisted_connection.id == connection.id

    {:ok, directory_user} =
      EnterpriseIdentity.link_directory_user(
        connection.id,
        membership.id,
        user.id,
        "directory-user-123"
      )

    assert directory_user.enterprise_connection_id == connection.id

    assert {:ok, loaded_directory_user} =
             EnterpriseIdentity.get_directory_user(directory_user.id,
               load: [:enterprise_connection, :membership]
             )

    assert loaded_directory_user.membership.id == membership.id
    assert loaded_directory_user.enterprise_connection.id == connection.id

    {:ok, directory} =
      EnterpriseIdentity.create_directory(connection.id, "directory-123")

    {:ok, directory_group} =
      EnterpriseIdentity.create_directory_group(directory.id, "group-123", "Reviewers")

    {:ok, _directory_membership} =
      EnterpriseIdentity.add_directory_user_to_group(directory_user.id, directory_group.id)

    {:ok, role} = Authorization.create_role(organization.id, "reviewer", "Reviewer")

    assert {:ok, group_role_mapping} =
             EnterpriseIdentity.map_directory_group_role(directory_group.id, role.id)

    assert group_role_mapping.directory_group_id == directory_group.id
    assert group_role_mapping.role_id == role.id

    {:ok, unrelated_organization} =
      Organizations.create_organization("Unrelated", "unrelated")

    {:ok, unrelated_role} =
      Authorization.create_role(unrelated_organization.id, "reviewer", "Reviewer")

    assert {:error, %Ash.Error.Invalid{} = mapping_error} =
             EnterpriseIdentity.map_directory_group_role(
               directory_group.id,
               unrelated_role.id
             )

    assert Exception.message(mapping_error) =~ "mapping scope mismatch"

    assert {:ok, loaded_user} =
             Accounts.get_user(user.id, load: [:directory_users, :directory_groups])

    assert Enum.map(loaded_user.directory_users, & &1.id) == [directory_user.id]
    assert Enum.map(loaded_user.directory_groups, & &1.id) == [directory_group.id]

    {:ok, other_organization} = Organizations.create_organization("Other", "other")
    {:ok, other_membership} = Organizations.add_member(other_organization.id, user.id)

    assert {:error, %Ash.Error.Invalid{} = error} =
             EnterpriseIdentity.link_directory_user(
               connection.id,
               other_membership.id,
               user.id,
               "directory-user-other"
             )

    assert Exception.message(error) =~ "identity scope mismatch"

    assert {:ok, deprovisioned_directory_user} =
             EnterpriseIdentity.deprovision_directory_user(directory_user)

    assert deprovisioned_directory_user.status == "inactive"
    assert {:ok, preserved_user} = Accounts.get_user(user.id)
    assert preserved_user.status == "active"
    refute Organizations.member?(organization.id, user.id)
    assert {:ok, _consumer_session} = Accounts.issue_session(user.id, %{})
  end
end
