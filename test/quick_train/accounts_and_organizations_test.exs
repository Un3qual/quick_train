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
    assert {:error, %Ash.Error.Invalid{} = error} =
             Accounts.issue_session(Ecto.UUID.generate(), %{authentication_method: "oidc"})

    assert Exception.message(error) =~ "account required"
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

    assert {:error, %Ash.Error.Invalid{} = error} =
             Accounts.issue_session(user.id, %{organization_id: organization.id})

    assert Exception.message(error) =~ "active membership required"

    assert {:ok, _membership} = Organizations.add_member(organization.id, user.id)
    assert {:ok, session} = Accounts.issue_session(user.id, %{organization_id: organization.id})
    assert session.organization_id == organization.id
  end

  test "authentication support records are managed through account actions" do
    assert {:ok, user} = Accounts.register_user("identity@example.com", "Identity")

    assert {:ok, identity} =
             Accounts.link_external_identity(user.id, "oidc", "provider-subject", %{
               claims: %{"email_verified" => true}
             })

    assert identity.user_id == user.id

    assert {:ok, persisted_identity} =
             Accounts.get_external_identity("oidc", "provider-subject")

    assert persisted_identity.id == identity.id

    expires_at = DateTime.add(DateTime.utc_now(), 5, :minute)

    assert {:ok, transaction} =
             Accounts.begin_oidc_login("state-hash", "code-verifier", expires_at, %{
               return_to: "/forms"
             })

    assert transaction.return_to == "/forms"
    assert {:ok, consumed_transaction} = Accounts.consume_oidc_login(transaction)
    assert %DateTime{} = consumed_transaction.consumed_at

    assert {:ok, event} =
             Accounts.record_authentication_event("oidc.callback", "succeeded", %{
               user_id: user.id
             })

    assert event.user_id == user.id
  end
end
