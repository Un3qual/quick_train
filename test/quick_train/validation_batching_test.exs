defmodule QuickTrain.ValidationBatchingTest do
  use QuickTrain.DataCase, async: false

  alias QuickTrain.{Accounts, Authorization, EnterpriseIdentity, Organizations}
  alias QuickTrain.Assets.Asset
  alias QuickTrain.Datasets.DatasetRecord.Values
  alias QuickTrain.EnterpriseIdentity.{DirectoryUser, ExternalGroupRoleMapping}

  alias QuickTrain.EnterpriseIdentity.DirectoryUser.Validations.IdentityScope

  alias QuickTrain.EnterpriseIdentity.ExternalGroupRoleMapping.Validations.MappingScope

  test "record asset validation batches duplicate identities and keeps organization scope" do
    organization = Organizations.create_organization!("Asset Batch", "asset-batch")
    other = Organizations.create_organization!("Other Asset Batch", "other-asset-batch")

    asset =
      Ash.Seed.seed!(Asset, %{
        organization_id: organization.id,
        state: :ready,
        sha256: <<170::256>>,
        byte_size: 4,
        media_type: "text/plain",
        staging_key: "batch/staging",
        sealed_key: "batch/sealed",
        staging_expires_at: DateTime.utc_now()
      })

    occurrences = List.duplicate(%{family: :asset, value: asset.id}, 20)

    {result, query_count} =
      count_repo_queries(fn -> Values.validate_assets(organization.id, occurrences) end)

    assert result == :ok
    assert query_count == 1
    assert {:error, :invalid_asset} = Values.validate_assets(other.id, occurrences)

    assert {:error, :invalid_asset} =
             Values.validate_assets(organization.id, [
               %{family: :asset, value: Ash.UUID.generate()}
             ])
  end

  test "authorization decisions use one filterable existence query" do
    {:ok, user} = Accounts.register_user("query-user@example.com", "Query User")
    {:ok, organization} = Organizations.create_organization("Query Org", "query-org")
    {:ok, _membership} = Organizations.add_member(organization.id, user.id)
    {:ok, role} = Authorization.create_role(organization.id, "query-role", "Query Role")
    {:ok, capability} = Authorization.create_capability("queries.run", "Run queries")
    {:ok, _grant} = Authorization.grant_capability(role.id, capability.id)
    {:ok, _assignment} = Authorization.assign_role(organization.id, user.id, role.id)

    {allowed?, query_count} =
      count_repo_queries(fn ->
        Authorization.allowed?(user.id, organization.id, capability.key)
      end)

    assert allowed?
    assert query_count == 1
  end

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
        &__MODULE__.handle_repo_query/4,
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

  def handle_repo_query(_event, _measurements, _metadata, {test_process, query_reference}) do
    send(test_process, {:repo_query, query_reference})
  end
end
