defmodule QuickTrain.ProductCapabilitiesTest do
  use QuickTrain.DataCase, async: true

  alias QuickTrain.{Accounts, Authorization, Datasets, Organizations}
  alias QuickTrain.Authorization.{Capability, RoleCapability}
  alias QuickTrain.Authorization.Checks.OrganizationCapability
  alias QuickTrain.Datasets.ProductCapabilities

  @capability_keys ~w(
    assets.read
    assets.manage
    datasets.read
    datasets.manage
    dataset_imports.manage
  )

  test "internal lifecycle actions reject even an organization manager" do
    user = Accounts.register_user!("internal-manager@example.test", "Internal Manager")
    graph = Accounts.bootstrap_first_manager!(user.id, "internal-org", "Internal Org")
    Datasets.grant_product_capabilities!(graph.organization.id, user.id)
    id = Ash.UUID.generate()

    operations = [
      fn -> QuickTrain.Assets.cleanup_asset_staging(id, actor: user) end,
      fn ->
        QuickTrain.Assets.reconcile_asset_publication(
          id,
          graph.organization.id,
          id,
          "sealed",
          %{},
          actor: user
        )
      end,
      fn -> Datasets.cleanup_expired_import(id, actor: user) end,
      fn -> Datasets.process_import_row(id, actor: user) end,
      fn -> Datasets.terminalize_import_row(id, actor: user) end,
      fn ->
        Datasets.put_candidate_revision(graph.organization.id, id, id, id, nil, id, actor: user)
      end,
      fn -> Datasets.construct_record(graph.organization.id, id, id, id, [], actor: user) end
    ]

    for operation <- operations do
      assert {:error, %Ash.Error.Forbidden{}} = operation.()
    end
  end

  test "grants the exact product capabilities to an existing manager idempotently" do
    user = Accounts.register_user!("product-manager@example.test", "Product Manager")
    graph = Accounts.bootstrap_first_manager!(user.id, "product-org", "Product Org")

    assert {:ok, first_keys} =
             Datasets.grant_product_capabilities(graph.organization.id, user.id)

    assert Enum.sort(first_keys) == Enum.sort(@capability_keys)

    capability_ids =
      Capability
      |> Ash.read!(authorize?: false)
      |> Map.new(&{&1.key, &1.id})

    assert Map.keys(capability_ids) |> Enum.sort() == Enum.sort(@capability_keys)
    assert Ash.count!(RoleCapability, authorize?: false) == 5

    assert {:ok, second_keys} =
             Datasets.grant_product_capabilities(graph.organization.id, user.id)

    assert Enum.sort(second_keys) == Enum.sort(@capability_keys)

    assert Capability
           |> Ash.read!(authorize?: false)
           |> Map.new(&{&1.key, &1.id}) == capability_ids

    assert Ash.count!(RoleCapability, authorize?: false) == 5

    assert Enum.all?(@capability_keys, fn key ->
             Authorization.allowed?(user.id, graph.organization.id, key)
           end)

    refute Authorization.allowed?(user.id, graph.organization.id, "assets.*")
  end

  test "refuses to grant product capabilities to a member without the manager role" do
    manager = Accounts.register_user!("manager@example.test", "Manager")
    graph = Accounts.bootstrap_first_manager!(manager.id, "managed-org", "Managed Org")
    member = Accounts.register_user!("member@example.test", "Member")
    Organizations.add_member!(graph.organization.id, member.id)

    assert {:error, error} =
             Datasets.grant_product_capabilities(graph.organization.id, member.id)

    assert Exception.message(error) =~ "product_capability_grant_conflict"
    assert Ash.count!(Capability, authorize?: false) == 0
    assert Ash.count!(RoleCapability, authorize?: false) == 0
  end

  test "the shared policy check derives organization scope and fails closed" do
    user = Accounts.register_user!("policy-manager@example.test", "Policy Manager")
    graph = Accounts.bootstrap_first_manager!(user.id, "policy-org", "Policy Org")
    Datasets.grant_product_capabilities!(graph.organization.id, user.id)

    input =
      Ash.ActionInput.for_action(ProductCapabilities, :grant_to_manager, %{
        organization_id: graph.organization.id,
        user_id: user.id
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
      Ash.ActionInput.for_action(ProductCapabilities, :grant_to_manager, %{
        organization_id: other_organization.id,
        user_id: user.id
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

    inactive_organization =
      graph.organization
      |> Ash.Changeset.for_update(:update, %{status: "inactive"}, authorize?: false)
      |> Ash.update!()

    refute OrganizationCapability.match?(
             user,
             %{subject: input},
             capability: "assets.read"
           )

    refute OrganizationCapability.match?(
             user,
             %{subject: nil},
             capability: "assets.read"
           )

    assert inactive_membership.status == "inactive"
    assert active_membership.status == "active"
    assert inactive_organization.status == "inactive"
  end
end
