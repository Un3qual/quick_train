defmodule QuickTrain.AuthenticationPersistenceTest do
  use QuickTrain.DataCase, async: true

  alias QuickTrain.Accounts

  test "login transactions persist hashed client proof and a trusted callback" do
    now = DateTime.utc_now()
    state_hash = :crypto.hash(:sha256, "state")
    nonce_hash = :crypto.hash(:sha256, "nonce")
    redemption_secret_hash = :crypto.hash(:sha256, "redemption-secret")

    transaction =
      Accounts.store_oidc_login!(%{
        state_hash: state_hash,
        nonce_hash: nonce_hash,
        code_verifier: "pkce-verifier",
        redemption_secret_hash: redemption_secret_hash,
        callback_key: "primary",
        callback_uri: "https://client.example.test/oidc/callback",
        expires_at: DateTime.add(now, 5, :minute),
        retain_until: DateTime.add(now, 1, :day)
      })

    assert transaction.status == "pending"
    assert transaction.state_hash == state_hash
    assert transaction.nonce_hash == nonce_hash
    assert transaction.redemption_secret_hash == redemption_secret_hash
    assert transaction.callback_key == "primary"
    assert transaction.callback_uri == "https://client.example.test/oidc/callback"
    refute Map.has_key?(transaction, :state)
    refute Map.has_key?(transaction, :nonce)
    refute Map.has_key?(transaction, :redemption_secret)
  end

  test "a consumed login transaction cannot be claimed or consumed again" do
    now = DateTime.utc_now()

    transaction =
      Accounts.store_oidc_login!(%{
        state_hash: :crypto.hash(:sha256, "state-#{System.unique_integer([:positive])}"),
        nonce_hash: :crypto.hash(:sha256, "nonce"),
        code_verifier: "pkce-verifier",
        redemption_secret_hash: :crypto.hash(:sha256, "redemption-secret"),
        callback_key: "primary",
        callback_uri: "https://client.example.test/oidc/callback",
        expires_at: DateTime.add(now, 5, :minute),
        retain_until: DateTime.add(now, 1, :day)
      })

    claimed = Accounts.claim_oidc_login!(transaction)
    consumed = Accounts.consume_oidc_login!(claimed)

    assert consumed.status == "consumed"
    assert {:error, _error} = Accounts.claim_oidc_login(consumed)
    assert {:error, _error} = Accounts.consume_oidc_login(consumed)
  end

  test "external identity issuer and subject cannot be reassigned by profile refresh" do
    user =
      Accounts.register_user!(
        "identity-#{System.unique_integer([:positive])}@example.com",
        "Identity"
      )

    identity =
      Accounts.create_external_identity!(%{
        user_id: user.id,
        issuer: "https://issuer.example.test",
        subject: "subject-1",
        claims: %{"email_verified" => true}
      })

    assert {:error, %Ash.Error.Invalid{}} =
             Accounts.refresh_external_identity(identity, %{
               issuer: "https://other-issuer.example.test",
               subject: "subject-2",
               user_id: Ecto.UUID.generate(),
               claims: %{"name" => "Updated"}
             })

    persisted = Accounts.get_external_identity!("https://issuer.example.test", "subject-1")
    assert persisted.user_id == user.id
    assert persisted.issuer == "https://issuer.example.test"
    assert persisted.subject == "subject-1"
  end

  test "bearer session records are global, hash-only, unique, and require an active user" do
    user =
      Accounts.register_user!(
        "session-#{System.unique_integer([:positive])}@example.com",
        "Session"
      )

    now = DateTime.utc_now()
    token_hash = :crypto.hash(:sha256, "opaque-token")

    session =
      Accounts.persist_bearer_session!(%{
        user_id: user.id,
        token_hash: token_hash,
        authentication_method: "oidc",
        issued_at: now,
        expires_at: DateTime.add(now, 8, :hour)
      })

    assert session.user_id == user.id
    assert session.token_hash == token_hash
    refute Map.has_key?(session, :token)
    refute Map.has_key?(session, :organization_id)

    assert {:error, %Ash.Error.Invalid{}} =
             Accounts.persist_bearer_session(%{
               user_id: user.id,
               token_hash: token_hash,
               authentication_method: "oidc",
               issued_at: now,
               expires_at: DateTime.add(now, 8, :hour)
             })

    disabled_user =
      user
      |> Ash.Changeset.for_update(:set_status, %{status: "disabled"}, authorize?: false)
      |> Ash.update!()

    assert {:error, %Ash.Error.Invalid{}} =
             Accounts.persist_bearer_session(%{
               user_id: disabled_user.id,
               token_hash: :crypto.hash(:sha256, "disabled-user-token"),
               authentication_method: "oidc",
               issued_at: now,
               expires_at: DateTime.add(now, 8, :hour)
             })
  end

  test "bearer issuance returns the opaque token once and persists only its hash" do
    user =
      Accounts.register_user!(
        "issued-session-#{System.unique_integer([:positive])}@example.com",
        "Issued Session"
      )

    issued = Accounts.issue_bearer_session!(user.id)

    assert is_binary(issued.token)
    assert byte_size(Base.url_decode64!(issued.token, padding: false)) == 32

    token_hash = :crypto.hash(:sha256, issued.token)
    session = Accounts.get_session_by_token_hash!(token_hash)

    assert session.id == issued.session_id
    assert session.user_id == user.id
    assert session.token_hash == token_hash

    assert DateTime.compare(session.expires_at, DateTime.add(session.issued_at, 8, :hour)) in [
             :lt,
             :eq
           ]

    refute Map.has_key?(session, :token)
    refute Map.has_key?(session, :organization_id)
  end
end
