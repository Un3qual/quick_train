defmodule QuickTrain.ValidationBatchingTest do
  use QuickTrain.DataCase, async: false

  alias QuickTrain.{Accounts, Authorization, EnterpriseIdentity, Organizations}
  alias QuickTrain.EnterpriseIdentity.{DirectoryUser, ExternalGroupRoleMapping}

  alias QuickTrain.EnterpriseIdentity.DirectoryUser.Validations.IdentityScope

  alias QuickTrain.EnterpriseIdentity.ExternalGroupRoleMapping.Validations.MappingScope

  test "directory-user scope validation batches related-record reads" do
    {:ok, user} = Accounts.register_user("batch-user@example.com", "Batch User")
    {:ok, organization} = Organizations.create_organization("Batch Org", "batch-org")
    {:ok, membership} = Organizations.add_member(organization.id, user.id)

    {:ok, connection} =
      EnterpriseIdentity.create_connection(organization.id, "workos", "batch-connection")

    {:ok, other_organization} =
      Organizations.create_organization("Other Batch Org", "other-batch-org")

    {:ok, other_membership} = Organizations.add_member(other_organization.id, user.id)

    changesets = [
      directory_user_changeset(connection.id, membership.id, user.id, "valid-1"),
      directory_user_changeset(connection.id, membership.id, user.id, "valid-2"),
      directory_user_changeset(connection.id, other_membership.id, user.id, "invalid")
    ]

    {validated, query_count} =
      count_repo_queries(fn ->
        IdentityScope.batch_validate(
          changesets,
          [],
          %Ash.Resource.Validation.Context{bulk?: true}
        )
      end)

    assert Enum.map(validated, & &1.valid?) == [true, true, false]
    assert query_count in 1..2
  end

  test "group-role mapping scope validation batches related-record reads" do
    {:ok, organization} = Organizations.create_organization("Mapping Org", "mapping-org")

    {:ok, connection} =
      EnterpriseIdentity.create_connection(organization.id, "workos", "mapping-connection")

    {:ok, directory} = EnterpriseIdentity.create_directory(connection.id, "mapping-directory")

    {:ok, directory_group} =
      EnterpriseIdentity.create_directory_group(directory.id, "mapping-group", "Mapping Group")

    {:ok, role} = Authorization.create_role(organization.id, "member", "Member")

    {:ok, other_organization} =
      Organizations.create_organization("Other Mapping Org", "other-mapping-org")

    {:ok, other_role} =
      Authorization.create_role(other_organization.id, "member", "Member")

    changesets = [
      mapping_changeset(directory_group.id, role.id),
      mapping_changeset(directory_group.id, role.id),
      mapping_changeset(directory_group.id, other_role.id)
    ]

    {validated, query_count} =
      count_repo_queries(fn ->
        MappingScope.batch_validate(
          changesets,
          [],
          %Ash.Resource.Validation.Context{bulk?: true}
        )
      end)

    assert Enum.map(validated, & &1.valid?) == [true, true, false]
    assert query_count in 1..4
  end

  defp directory_user_changeset(connection_id, membership_id, user_id, external_id) do
    DirectoryUser
    |> Ash.Changeset.new()
    |> Ash.Changeset.force_change_attributes(%{
      enterprise_connection_id: connection_id,
      membership_id: membership_id,
      user_id: user_id,
      external_id: external_id
    })
  end

  defp mapping_changeset(directory_group_id, role_id) do
    ExternalGroupRoleMapping
    |> Ash.Changeset.new()
    |> Ash.Changeset.force_change_attributes(%{
      directory_group_id: directory_group_id,
      role_id: role_id
    })
  end

  defp count_repo_queries(fun) do
    reference = make_ref()
    handler_id = {__MODULE__, reference}

    :ok =
      :telemetry.attach(
        handler_id,
        [:quick_train, :repo, :query],
        fn _event, _measurements, _metadata, {test_process, query_reference} ->
          send(test_process, {:repo_query, query_reference})
        end,
        {self(), reference}
      )

    try do
      result = fun.()
      {result, drain_query_count(reference, 0)}
    after
      :telemetry.detach(handler_id)
    end
  end

  defp drain_query_count(reference, count) do
    receive do
      {:repo_query, ^reference} -> drain_query_count(reference, count + 1)
    after
      0 -> count
    end
  end
end
