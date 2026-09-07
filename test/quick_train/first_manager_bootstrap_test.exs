defmodule QuickTrain.FirstManagerBootstrapTest do
  use QuickTrain.DataCase, async: false

  import ExUnit.CaptureIO

  require Ash.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Mix.Tasks.QuickTrain.BootstrapFirstManager
  alias QuickTrain.{Accounts, Datasets}
  alias QuickTrain.Accounts.User
  alias QuickTrain.Authorization.{Capability, Role, RoleAssignment, RoleCapability}
  alias QuickTrain.Organizations.{Membership, Organization}

  @tag :committed_db
  test "a capability grant waiting for the user cannot deadlock manager bootstrap" do
    user = Accounts.register_user!("lock-manager@example.test", "Lock Manager")
    graph = Accounts.bootstrap_first_manager!(user.id, "lock-org", "Lock Org")
    parent = self()

    grant =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          %{rows: [[backend_id]]} = Repo.query!("SELECT pg_backend_pid()")
          send(parent, {:grant_connection, backend_id})
          receive do: (:go -> Datasets.grant_product_capabilities(graph.organization.id, user.id))
        end)
      end)

    try do
      assert_receive {:grant_connection, backend_id}, 5_000

      assert {:ok, _graph} =
               Ash.transact(User, fn ->
                 User
                 |> Ash.Query.filter(id == ^user.id)
                 |> Ash.Query.lock(:for_update)
                 |> Ash.read_one!(authorize?: false)

                 send(grant.pid, :go)
                 await_database_lock(backend_id, System.monotonic_time(:millisecond) + 5_000)
                 Accounts.bootstrap_first_manager!(user.id, "lock-org", "Lock Org")
               end)

      assert {:ok, capabilities} = Task.await(grant, 5_000)
      assert "datasets.manage" in capabilities
    after
      Task.shutdown(grant, :brutal_kill)
    end
  end

  defp await_database_lock(backend_id, deadline) do
    case Repo.query!("SELECT pg_blocking_pids($1)", [backend_id]).rows do
      [[[_blocker | _rest]]] ->
        :ok

      [[[]]] ->
        assert System.monotonic_time(:millisecond) < deadline,
               "grant did not reach its database lock"

        Process.sleep(10)
        await_database_lock(backend_id, deadline)
    end
  end

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

  @tag :committed_db
  test "matching repeated and concurrent requests converge on one graph" do
    user = Accounts.register_user!("repeat-manager@example.test", "Manager")

    first = Accounts.bootstrap_first_manager!(user.id, "repeat-org", "Repeat Org")
    second = Accounts.bootstrap_first_manager!(user.id, "repeat-org", "Repeat Org")

    assert second.organization.id == first.organization.id
    assert second.membership.id == first.membership.id
    assert second.role.id == first.role.id
    assert second.assignment.id == first.assignment.id

    concurrent_results =
      concurrently(
        for _attempt <- 1..2 do
          fn -> Accounts.bootstrap_first_manager(user.id, "concurrent-org", "Concurrent Org") end
        end
      )

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

  test "a role conflict rolls back membership created earlier in the bootstrap" do
    user = Accounts.register_user!("role-conflict-manager@example.test", "Manager")
    organization = QuickTrain.Organizations.create_organization!("Role Conflict", "role-conflict")

    _conflicting_role =
      QuickTrain.Authorization.create_role!(organization.id, "manager", "Not Manager")

    assert {:error, error} =
             Accounts.bootstrap_first_manager(
               user.id,
               organization.slug,
               organization.name
             )

    assert Exception.message(error) =~ "bootstrap_conflict"
    assert Ash.count!(Membership, authorize?: false) == 0
    assert Ash.count!(RoleAssignment, authorize?: false) == 0
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
