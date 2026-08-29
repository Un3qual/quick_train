defmodule QuickTrain.AuthenticationRetentionTest do
  use QuickTrain.DataCase, async: false
  use Oban.Testing, repo: QuickTrain.Repo

  alias QuickTrain.Accounts
  alias QuickTrain.Accounts.{OidcLoginTransaction, Session}
  alias QuickTrain.Accounts.Workers.AuthenticationRetention

  test "worker idempotently removes only login state beyond its retention cutoff" do
    now = DateTime.utc_now()

    stale_pending = seed_login("stale-pending", "pending", now, -2, -1)
    stale_claimed = seed_login("stale-claimed", "exchanging", now, -2, -1)
    stale_consumed = seed_login("stale-consumed", "consumed", now, -2, -1)
    live_pending = seed_login("live-pending", "pending", now, 1, 2)

    assert :ok = perform_job(AuthenticationRetention, %{})
    assert :ok = perform_job(AuthenticationRetention, %{})

    for transaction <- [stale_pending, stale_claimed, stale_consumed] do
      assert Accounts.get_oidc_login(
               transaction.state_hash,
               authorize?: false,
               not_found_error?: false
             ) == {:ok, nil}
    end

    assert Accounts.get_oidc_login!(live_pending.state_hash).id == live_pending.id
  end

  test "session cleanup waits for retention after the later expiry or revocation" do
    original_authentication = Application.get_env(:quick_train, :authentication)

    Application.put_env(
      :quick_train,
      :authentication,
      Keyword.put(original_authentication || [], :session_retention_seconds, 86_400)
    )

    on_exit(fn -> restore_env(:authentication, original_authentication) end)

    user = Accounts.register_user!("retention@example.test", "Retention")
    now = DateTime.utc_now()

    stale_expired = seed_session(user.id, "stale-expired", now, -2, nil)
    stale_revoked = seed_session(user.id, "stale-revoked", now, -2, -3)
    recently_expired = seed_session(user.id, "recently-expired", now, -1, nil, :hour)
    revoked_before_future_expiry = seed_session(user.id, "future-expiry", now, 1, -2)
    active = seed_session(user.id, "active", now, 1, nil)

    disabled_user = Accounts.register_user!("disabled-retained@example.test", "Disabled")
    disabled_issued = Accounts.issue_bearer_session!(disabled_user.id)

    _disabled_user =
      disabled_user
      |> Ash.Changeset.for_update(:set_status, %{status: "disabled"}, authorize?: false)
      |> Ash.update!()

    assert :ok = perform_job(AuthenticationRetention, %{})

    for session <- [stale_expired, stale_revoked] do
      assert Accounts.get_session_by_token_hash(
               session.token_hash,
               authorize?: false,
               not_found_error?: false
             ) == {:ok, nil}
    end

    for session <- [recently_expired, revoked_before_future_expiry, active] do
      assert Accounts.get_session_by_token_hash!(session.token_hash).id == session.id
    end

    disabled_hash = :crypto.hash(:sha256, disabled_issued.token)
    assert Accounts.get_session_by_token_hash!(disabled_hash).user_id == disabled_user.id
  end

  test "worker schedule is fixed and overlapping jobs are unique" do
    oban_config = Application.fetch_env!(:quick_train, Oban)

    assert {"17 * * * *", AuthenticationRetention} in oban_config[:cron][:crontab]

    {:ok, first_job} = Oban.insert(AuthenticationRetention.new(%{}))
    {:ok, second_job} = Oban.insert(AuthenticationRetention.new(%{}))

    assert second_job.conflict?
    assert second_job.id == first_job.id
  end

  defp seed_login(label, status, now, expires_days, retain_days) do
    Ash.Seed.seed!(OidcLoginTransaction, %{
      state_hash: :crypto.hash(:sha256, "state-#{label}"),
      nonce_hash: :crypto.hash(:sha256, "nonce-#{label}"),
      code_verifier: "verifier-#{label}",
      redemption_secret_hash: :crypto.hash(:sha256, "proof-#{label}"),
      callback_key: "desktop",
      callback_uri: "http://127.0.0.1:4173/oidc/callback",
      status: status,
      expires_at: DateTime.add(now, expires_days, :day),
      retain_until: DateTime.add(now, retain_days, :day)
    })
  end

  defp seed_session(user_id, label, now, expires_amount, revoked_days, unit \\ :day) do
    Ash.Seed.seed!(Session, %{
      user_id: user_id,
      authentication_method: "oidc",
      token_hash: :crypto.hash(:sha256, "token-#{label}"),
      issued_at: DateTime.add(now, -4, :day),
      expires_at: DateTime.add(now, expires_amount, unit),
      revoked_at: revoked_at(now, revoked_days)
    })
  end

  defp revoked_at(_now, nil), do: nil
  defp revoked_at(now, days), do: DateTime.add(now, days, :day)

  defp restore_env(key, nil), do: Application.delete_env(:quick_train, key)
  defp restore_env(key, value), do: Application.put_env(:quick_train, key, value)
end
