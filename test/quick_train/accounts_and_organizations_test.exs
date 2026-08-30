defmodule QuickTrain.AccountsAndOrganizationsTest do
  use QuickTrain.DataCase, async: true

  alias QuickTrain.{Accounts, Organizations}

  test "consumer accounts do not require an organization membership" do
    assert {:ok, user} = Accounts.register_user("  CONSUMER@Example.COM  ", "Consumer")
    assert user.email == "consumer@example.com"
  end

  test "all sessions require a registered user" do
    assert {:error, %Ash.Error.Invalid{}} =
             Accounts.persist_bearer_session(session_attrs(Ecto.UUID.generate(), "missing-user"))
  end

  test "disabled accounts cannot start sessions" do
    assert {:ok, user} = Accounts.register_user("disabled@example.com", "Disabled")

    user =
      user
      |> Ash.Changeset.for_update(:set_status, %{status: "disabled"}, authorize?: false)
      |> Ash.update!()

    assert {:error, %Ash.Error.Invalid{}} =
             Accounts.persist_bearer_session(session_attrs(user.id, "disabled-user"))
  end

  test "the same user can be an organization member and a consumer" do
    assert {:ok, user} = Accounts.register_user("member@example.com", "Member")
    assert {:ok, organization} = Organizations.create_organization("Example Corp", "example-corp")
    assert {:ok, membership} = Organizations.add_member(organization.id, user.id)

    assert membership.user_id == user.id
    assert Organizations.member?(organization.id, user.id)

    assert {:ok, session} =
             Accounts.persist_bearer_session(session_attrs(user.id, "member-consumer"))

    refute Map.has_key?(session, :organization_id)
  end

  test "membership state does not become bearer-session authority" do
    assert {:ok, user} = Accounts.register_user("inactive-member@example.com", "Inactive")
    assert {:ok, organization} = Organizations.create_organization("Dormant", "dormant")
    assert {:ok, membership} = Organizations.add_member(organization.id, user.id)
    assert Organizations.member?(organization.id, user.id)

    assert {:ok, _membership} = Organizations.deactivate_membership(membership)
    refute Organizations.member?(organization.id, user.id)

    assert {:ok, session} =
             Accounts.persist_bearer_session(session_attrs(user.id, "inactive-membership"))

    assert session.user_id == user.id
    refute Map.has_key?(session, :organization_id)
  end

  test "authentication events are managed through account actions" do
    assert {:ok, user} = Accounts.register_user("identity@example.com", "Identity")

    assert {:ok, event} =
             Accounts.record_authentication_event("oidc.callback", "succeeded", %{
               user_id: user.id
             })

    assert event.user_id == user.id
  end

  defp session_attrs(user_id, token_seed) do
    now = DateTime.utc_now()

    %{
      user_id: user_id,
      token_hash: :crypto.hash(:sha256, token_seed),
      authentication_method: "oidc",
      issued_at: now,
      expires_at: DateTime.add(now, 8, :hour)
    }
  end
end
