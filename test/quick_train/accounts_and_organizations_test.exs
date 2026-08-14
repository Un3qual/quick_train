defmodule QuickTrain.AccountsAndOrganizationsTest do
  use QuickTrain.DataCase, async: true

  alias QuickTrain.{Accounts, Organizations}

  test "consumer accounts do not require an organization membership" do
    assert {:ok, user} = Accounts.register_user("  CONSUMER@Example.COM  ", "Consumer")
    assert user.email == "consumer@example.com"

    assert {:ok, session} = Accounts.issue_session(user.id, %{authentication_method: "oidc"})
    assert session.user_id == user.id
    assert session.organization_id == nil
  end

  test "all sessions require a registered user" do
    assert {:error, :account_required} =
             Accounts.issue_session(Ecto.UUID.generate(), %{authentication_method: "oidc"})
  end

  test "the same user can be an organization member and a consumer" do
    assert {:ok, user} = Accounts.register_user("member@example.com", "Member")
    assert {:ok, organization} = Organizations.create_organization("Example Corp", "example-corp")
    assert {:ok, membership} = Organizations.add_member(organization.id, user.id)

    assert membership.user_id == user.id
    assert Organizations.member?(organization.id, user.id)
    assert {:ok, consumer_session} = Accounts.issue_session(user.id, %{})
    assert consumer_session.organization_id == nil
  end

  test "organization sessions require an active membership" do
    assert {:ok, user} = Accounts.register_user("scoped@example.com", "Scoped")
    assert {:ok, organization} = Organizations.create_organization("Acme", "acme")

    assert {:error, :membership_required} =
             Accounts.issue_session(user.id, %{organization_id: organization.id})

    assert {:ok, _membership} = Organizations.add_member(organization.id, user.id)
    assert {:ok, session} = Accounts.issue_session(user.id, %{organization_id: organization.id})
    assert session.organization_id == organization.id
  end
end
