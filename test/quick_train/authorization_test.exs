defmodule QuickTrain.AuthorizationTest do
  use QuickTrain.DataCase, async: true

  alias QuickTrain.{Accounts, Authorization, Organizations}

  test "capability decisions are scoped to an organization and fail closed" do
    {:ok, user} = Accounts.register_user("owner@example.com", "Owner")
    {:ok, organization} = Organizations.create_organization("First", "first")
    {:ok, other_organization} = Organizations.create_organization("Second", "second")
    {:ok, _membership} = Organizations.add_member(organization.id, user.id)
    {:ok, role} = Authorization.create_role(organization.id, "owner", "Owner")
    {:ok, capability} = Authorization.create_capability("forms.manage", "Manage forms")
    {:ok, _grant} = Authorization.grant_capability(role.id, capability.id)
    {:ok, _assignment} = Authorization.assign_role(organization.id, user.id, role.id)

    assert {:error, %Ash.Error.Invalid{}} =
             Authorization.assign_role(
               organization.id,
               Ecto.UUID.generate(),
               role.id
             )

    {:ok, outsider} = Accounts.register_user("outsider@example.com", "Outsider")

    assert {:error, %Ash.Error.Forbidden{}} =
             Authorization.assign_role(organization.id, outsider.id, role.id)

    {:ok, _other_membership} = Organizations.add_member(other_organization.id, user.id)

    assert {:error, %Ash.Error.Forbidden{}} =
             Authorization.assign_role(other_organization.id, user.id, role.id)

    assert Authorization.allowed?(user.id, organization.id, "forms.manage")
    refute Authorization.allowed?(user.id, other_organization.id, "forms.manage")
    refute Authorization.allowed?(user.id, organization.id, "unknown.capability")
    refute Authorization.allowed?(Ecto.UUID.generate(), organization.id, "forms.manage")

    assert {:ok, decision} =
             Authorization.record_decision(
               user.id,
               organization.id,
               "forms.manage",
               true,
               "role capability granted"
             )

    assert decision.user_id == user.id
    assert decision.organization_id == organization.id
  end
end
