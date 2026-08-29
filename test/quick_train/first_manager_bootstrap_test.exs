defmodule QuickTrain.FirstManagerBootstrapTest do
  use QuickTrain.DataCase, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.QuickTrain.BootstrapFirstManager
  alias QuickTrain.Accounts
  alias QuickTrain.Authorization.{Capability, Role, RoleAssignment, RoleCapability}
  alias QuickTrain.Organizations.{Membership, Organization}

  test "bootstraps the exact first-manager graph without capability grants" do
    user = Accounts.register_user!("manager@example.test", "Manager")

    result =
      Accounts.bootstrap_first_manager!(
        user.id,
        "  ACME-Training  ",
        "  Acme Training  "
      )

    assert result.user.id == user.id
    assert result.organization.slug == "acme-training"
    assert result.organization.name == "Acme Training"
    assert result.organization.status == "active"
    assert result.membership.organization_id == result.organization.id
    assert result.membership.user_id == user.id
    assert result.membership.status == "active"
    assert result.role.organization_id == result.organization.id
    assert result.role.key == "manager"
    assert result.role.name == "Manager"
    assert result.assignment.organization_id == result.organization.id
    assert result.assignment.user_id == user.id
    assert result.assignment.role_id == result.role.id
    assert Ash.count!(Capability, authorize?: false) == 0
    assert Ash.count!(RoleCapability, authorize?: false) == 0
  end

  test "matching repeated and concurrent requests converge on one graph" do
    user = Accounts.register_user!("repeat-manager@example.test", "Manager")

    first = Accounts.bootstrap_first_manager!(user.id, "repeat-org", "Repeat Org")
    second = Accounts.bootstrap_first_manager!(user.id, "repeat-org", "Repeat Org")

    assert second.organization.id == first.organization.id
    assert second.membership.id == first.membership.id
    assert second.role.id == first.role.id
    assert second.assignment.id == first.assignment.id

    concurrent_results =
      1..2
      |> Enum.map(fn _attempt ->
        Task.async(fn ->
          Accounts.bootstrap_first_manager(user.id, "concurrent-org", "Concurrent Org")
        end)
      end)
      |> Task.await_many()

    assert Enum.all?(concurrent_results, &match?({:ok, _graph}, &1))

    assert concurrent_results
           |> Enum.map(fn {:ok, graph} -> graph.organization.id end)
           |> Enum.uniq()
           |> length() == 1

    assert Ash.count!(Organization, authorize?: false) == 2
    assert Ash.count!(Membership, authorize?: false) == 2
    assert Ash.count!(Role, authorize?: false) == 2
    assert Ash.count!(RoleAssignment, authorize?: false) == 2
  end

  test "conflicting or inactive facts fail atomically" do
    user = Accounts.register_user!("conflict-manager@example.test", "Manager")
    _organization = QuickTrain.Organizations.create_organization!("Other Name", "conflict-org")

    assert {:error, name_error} =
             Accounts.bootstrap_first_manager(user.id, "conflict-org", "Expected Name")

    assert Exception.message(name_error) =~ "bootstrap_conflict"
    assert Ash.count!(Membership, authorize?: false) == 0
    assert Ash.count!(Role, authorize?: false) == 0
    assert Ash.count!(RoleAssignment, authorize?: false) == 0

    disabled_user =
      user
      |> Ash.Changeset.for_update(:set_status, %{status: "disabled"}, authorize?: false)
      |> Ash.update!()

    assert {:error, inactive_error} =
             Accounts.bootstrap_first_manager(
               disabled_user.id,
               "new-org",
               "New Org"
             )

    assert Exception.message(inactive_error) =~ "bootstrap_conflict"
    assert Ash.count!(Organization, authorize?: false) == 1
  end

  test "operator Mix task accepts only the explicit graph identities" do
    user = Accounts.register_user!("cli-manager@example.test", "CLI Manager")
    Mix.Task.reenable("quick_train.bootstrap_first_manager")

    output =
      capture_io(fn ->
        BootstrapFirstManager.run([
          "--user-id",
          user.id,
          "--organization-slug",
          "cli-org",
          "--organization-name",
          "CLI Org"
        ])
      end)

    assert output =~ "Bootstrapped manager #{user.id} for organization cli-org"
    assert Ash.count!(Capability, authorize?: false) == 0
    assert Ash.count!(RoleCapability, authorize?: false) == 0
  end
end
