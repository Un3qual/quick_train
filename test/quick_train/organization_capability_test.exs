defmodule QuickTrain.OrganizationCapabilityTest do
  use QuickTrain.DataCase, async: true

  alias QuickTrain.{Accounts, Datasets, Organizations}
  alias QuickTrain.Assets.Asset
  alias QuickTrain.Authorization.Checks.OrganizationCapability

  test "internal lifecycle actions reject even an organization manager" do
    user = Accounts.register_user!("internal-manager@example.test", "Internal Manager")
    graph = organization_manager_fixture(user.id, "internal-org", "Internal Org")
    id = Ash.UUID.generate()

    operations = [
      fn -> Datasets.process_import_row(id, actor: user) end,
      fn ->
        Datasets.put_candidate_revision(graph.organization.id, id, id, id, nil, id, actor: user)
      end,
      fn -> Datasets.construct_record(graph.organization.id, id, id, id, [], actor: user) end
    ]

    for operation <- operations do
      assert {:error, %Ash.Error.Forbidden{}} = operation.()
    end
  end

  test "the shared policy check derives organization scope and fails closed" do
    user = Accounts.register_user!("policy-manager@example.test", "Policy Manager")
    graph = organization_manager_fixture(user.id, "policy-org", "Policy Org")

    input =
      Ash.ActionInput.for_action(Asset, :finalize, %{
        organization_id: graph.organization.id,
        asset_id: Ash.UUID.generate()
      })

    assert OrganizationCapability.match?(
             user,
             %{subject: input},
             capability: "assets.read"
           )

    refute OrganizationCapability.match?(
             user,
             %{subject: input},
             capability: "assets.*"
           )

    other_organization = Organizations.create_organization!("Other", "other-policy-org")

    other_input =
      Ash.ActionInput.for_action(Asset, :finalize, %{
        organization_id: other_organization.id,
        asset_id: Ash.UUID.generate()
      })

    refute OrganizationCapability.match?(
             user,
             %{subject: other_input},
             capability: "assets.read"
           )

    inactive_membership = Organizations.deactivate_membership!(graph.membership)

    refute OrganizationCapability.match?(
             user,
             %{subject: input},
             capability: "assets.read"
           )

    active_membership = Organizations.add_member!(graph.organization.id, user.id)

    disabled_user =
      user
      |> Ash.Changeset.for_update(:set_status, %{status: "disabled"}, authorize?: false)
      |> Ash.update!()

    refute OrganizationCapability.match?(
             disabled_user,
             %{subject: input},
             capability: "assets.read"
           )

    _active_user =
      disabled_user
      |> Ash.Changeset.for_update(:set_status, %{status: "active"}, authorize?: false)
      |> Ash.update!()

    refute OrganizationCapability.match?(
             user,
             %{subject: nil},
             capability: "assets.read"
           )

    inactive_organization =
      graph.organization
      |> Ash.Changeset.for_update(:update, %{status: "inactive"}, authorize?: false)
      |> Ash.update!()

    refute OrganizationCapability.match?(
             user,
             %{subject: input},
             capability: "assets.read"
           )

    assert inactive_membership.status == "inactive"
    assert active_membership.status == "active"
    assert inactive_organization.status == "inactive"
  end
end
