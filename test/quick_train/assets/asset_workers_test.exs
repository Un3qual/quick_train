defmodule QuickTrain.Assets.AssetWorkersTest do
  use QuickTrain.DataCase, async: false
  use Oban.Testing, repo: QuickTrain.Repo

  alias QuickTrain.{Accounts, Assets, Datasets}
  alias QuickTrain.Assets.Asset
  alias QuickTrain.Assets.Asset.{Actions.Finalize, Cleanup}
  alias QuickTrain.Assets.Storage
  alias QuickTrain.Assets.Storage.Test, as: TestStorage
  alias QuickTrain.Assets.Workers.{AssetStagingCleanup, VerifyAsset}

  setup do
    :ok = TestStorage.reset()

    manager = Accounts.register_user!("asset-worker@example.test", "Asset Worker")
    graph = Accounts.bootstrap_first_manager!(manager.id, "asset-worker-org", "Asset Worker Org")
    Datasets.grant_product_capabilities!(graph.organization.id, manager.id)

    %{manager: manager, graph: graph}
  end

  test "verification enqueue is unique and the worker finalizes from resource identity only", %{
    manager: manager,
    graph: graph
  } do
    content = "worker verified"

    registration =
      Assets.register_asset!(
        graph.organization.id,
        sha256(content),
        byte_size(content),
        "text/plain",
        actor: manager
      )

    :ok = TestStorage.put_staging(registration.upload_access, content)

    assert {:ok, first_job} = VerifyAsset.enqueue(registration.asset.id)
    assert {:ok, second_job} = VerifyAsset.enqueue(registration.asset.id)
    assert second_job.conflict?
    assert second_job.id == first_job.id
    assert first_job.args == %{asset_id: registration.asset.id}

    assert :ok = perform_job(VerifyAsset, %{"asset_id" => registration.asset.id})
    assert Ash.get!(Asset, registration.asset.id, authorize?: false).state == "ready"
  end

  test "verification failure before a terminal commit remains retryable", %{
    manager: manager,
    graph: graph
  } do
    content = "retry verified"

    registration =
      Assets.register_asset!(
        graph.organization.id,
        sha256(content),
        byte_size(content),
        "text/plain",
        actor: manager
      )

    assert {:error, :staging_missing} =
             perform_job(VerifyAsset, %{"asset_id" => registration.asset.id})

    assert Ash.get!(Asset, registration.asset.id, authorize?: false).state == "pending"
    :ok = TestStorage.put_staging(registration.upload_access, content)
    assert :ok = perform_job(VerifyAsset, %{"asset_id" => registration.asset.id})
    assert Ash.get!(Asset, registration.asset.id, authorize?: false).state == "ready"
  end

  test "cleanup scans expired uncleaned assets and records confirmed absence", %{graph: graph} do
    now = DateTime.utc_now()

    asset =
      Ash.Seed.seed!(Asset, %{
        organization_id: graph.organization.id,
        state: "pending",
        sha256: String.duplicate("a", 64),
        byte_size: 4,
        media_type: "text/plain",
        staging_key: "assets/staging/#{graph.organization.id}/abandoned",
        staging_expires_at: DateTime.add(now, -2, :hour)
      })

    assert :ok =
             Storage.retire_staging(
               asset.staging_key,
               DateTime.add(now, -1, :hour),
               1_000
             )

    assert :ok = perform_job(AssetStagingCleanup, %{})

    cleaned = Ash.get!(Asset, asset.id, authorize?: false)
    assert cleaned.state == "failed"
    assert cleaned.failure_reason == "staging_expired"
    assert %DateTime{} = cleaned.staging_cleaned_at
    assert is_nil(cleaned.operation_claim_id)

    assert :ok = perform_job(AssetStagingCleanup, %{})

    assert Ash.get!(Asset, asset.id, authorize?: false).staging_cleaned_at ==
             cleaned.staging_cleaned_at

    assert {:ok, remaining} = Cleanup.expired_assets(Asset, DateTime.utc_now(), 100)
    refute Enum.any?(remaining, &(&1.id == asset.id))
  end

  test "cleanup cannot replace a live finalization claim and fences a stale claimant", %{
    graph: graph
  } do
    now = DateTime.utc_now()
    live_claim_id = Ecto.UUID.generate()

    claimed =
      seed_asset(graph.organization.id, %{
        staging_expires_at: DateTime.add(now, -2, :hour),
        operation_claim_kind: "finalize",
        operation_claim_id: live_claim_id,
        operation_claim_expires_at: DateTime.add(now, 1, :hour)
      })

    assert :ok = perform_job(AssetStagingCleanup, %{})
    still_claimed = Ash.get!(Asset, claimed.id, authorize?: false)
    assert still_claimed.operation_claim_id == live_claim_id
    assert is_nil(still_claimed.staging_cleaned_at)

    expired =
      still_claimed
      |> Ash.Changeset.for_update(:start_publication, %{
        operation_claim_expires_at: DateTime.add(now, -1, :second)
      })
      |> Ash.update!(authorize?: false)

    assert expired.operation_claim_id == live_claim_id
    assert :ok = perform_job(AssetStagingCleanup, %{})
    cleaned = Ash.get!(Asset, claimed.id, authorize?: false)
    assert cleaned.state == "failed"
    assert %DateTime{} = cleaned.staging_cleaned_at

    current_claim_id = Ecto.UUID.generate()

    pending =
      seed_asset(graph.organization.id, %{
        staging_expires_at: DateTime.add(now, 1, :hour),
        operation_claim_kind: "cleanup",
        operation_claim_id: current_claim_id,
        operation_claim_expires_at: DateTime.add(now, 1, :hour)
      })

    assert {:error, :stale_asset_claim} =
             Finalize.reconcile_verified(
               Asset,
               pending.id,
               pending.organization_id,
               Ecto.UUID.generate(),
               sealed_key(pending),
               expected_facts(pending)
             )

    assert Ash.get!(Asset, pending.id, authorize?: false).state == "pending"
  end

  test "cleanup adopts a publication that committed before its database transition", %{
    graph: graph
  } do
    content = "published before commit"
    now = DateTime.utc_now()
    staging_key = "assets/staging/#{graph.organization.id}/published-before-commit"
    expected = expected(content)
    sealed_key = "assets/sealed/#{graph.organization.id}/#{expected.sha256}"
    access_expires_at = DateTime.add(now, 1, :second)

    descriptor =
      Storage.writable_staging_access!(staging_key, byte_size(content), access_expires_at)

    :ok = TestStorage.put_staging(descriptor, content)

    assert {:ok, _published} =
             Storage.verify_and_publish(staging_key, sealed_key, expected, 1_000)

    asset =
      seed_asset(graph.organization.id, %{
        sha256: expected.sha256,
        byte_size: expected.byte_size,
        media_type: expected.media_type,
        staging_key: staging_key,
        staging_expires_at: DateTime.add(now, -2, :hour),
        operation_claim_kind: "finalize",
        operation_claim_id: Ecto.UUID.generate(),
        operation_claim_expires_at: DateTime.add(now, -1, :second),
        publication_may_finish_at: DateTime.add(now, -1, :second)
      })

    assert :ok = perform_job(AssetStagingCleanup, %{})
    reconciled = Ash.get!(Asset, asset.id, authorize?: false)
    assert reconciled.state == "ready"

    Process.sleep(1_100)
    assert :ok = perform_job(AssetStagingCleanup, %{})
    cleaned = Ash.get!(Asset, asset.id, authorize?: false)
    assert %DateTime{} = cleaned.staging_cleaned_at

    {:ok, read_access} =
      Storage.sealed_read_access(sealed_key, DateTime.add(DateTime.utc_now(), 60))

    assert {:ok, ^content} = TestStorage.read_sealed(read_access)

    duplicate =
      seed_asset(graph.organization.id, %{
        state: "duplicate_content",
        sha256: expected.sha256,
        byte_size: expected.byte_size,
        media_type: expected.media_type,
        staging_key: "assets/staging/#{graph.organization.id}/duplicate-cleanup",
        staging_expires_at: DateTime.add(now, -2, :hour),
        failure_reason: "duplicate_content",
        canonical_asset_id: cleaned.id
      })

    assert :ok = perform_job(AssetStagingCleanup, %{})
    cleaned_duplicate = Ash.get!(Asset, duplicate.id, authorize?: false)
    assert cleaned_duplicate.state == "duplicate_content"
    assert %DateTime{} = cleaned_duplicate.staging_cleaned_at
    assert {:ok, ^content} = TestStorage.read_sealed(read_access)
  end

  test "a publication that outlives its claim is reconciled by cleanup", %{
    manager: manager,
    graph: graph
  } do
    original_assets = Application.fetch_env!(:quick_train, :assets)

    test_assets =
      original_assets
      |> Keyword.put(:operation_claim_seconds, 1)
      |> Keyword.put(:provider_in_flight_seconds, 1)
      |> Keyword.put(:staging_lifetime_seconds, 2)
      |> Keyword.put(:upload_access_lifetime_seconds, 2)
      |> Keyword.put(:cleanup_grace_seconds, 0)

    Application.put_env(:quick_train, :assets, test_assets)
    on_exit(fn -> Application.put_env(:quick_train, :assets, original_assets) end)
    :ok = TestStorage.set_publish_delay(1_100)

    content = "late publication"

    registration =
      Assets.register_asset!(
        graph.organization.id,
        sha256(content),
        byte_size(content),
        "text/plain",
        actor: manager
      )

    :ok = TestStorage.put_staging(registration.upload_access, content)

    assert {:error, :stale_asset_claim} =
             Finalize.finalize(Asset, registration.asset.id, graph.organization.id)

    published_but_pending = Ash.get!(Asset, registration.asset.id, authorize?: false)
    assert published_but_pending.state == "pending"
    assert TestStorage.sealed?(sealed_key(published_but_pending))

    wait_until = published_but_pending.staging_expires_at
    remaining_ms = max(DateTime.diff(wait_until, DateTime.utc_now(), :millisecond) + 50, 0)
    Process.sleep(remaining_ms)

    assert {:ok, _status} = Cleanup.cleanup(Asset, published_but_pending.id)
    reconciled = Ash.get!(Asset, published_but_pending.id, authorize?: false)
    assert reconciled.state == "ready"
    assert %DateTime{} = reconciled.staging_cleaned_at
    assert TestStorage.sealed?(sealed_key(reconciled))
  end

  test "cleanup schedule is fixed and overlapping scans are unique" do
    oban_config = Application.fetch_env!(:quick_train, Oban)

    assert {"*/10 * * * *", AssetStagingCleanup} in oban_config[:cron][:crontab]

    {:ok, first_job} = Oban.insert(AssetStagingCleanup.new(%{}))
    {:ok, second_job} = Oban.insert(AssetStagingCleanup.new(%{}))

    assert second_job.conflict?
    assert second_job.id == first_job.id
  end

  defp sha256(content),
    do: Base.encode16(:crypto.hash(:sha256, content), case: :lower)

  defp expected(content) do
    %{sha256: sha256(content), byte_size: byte_size(content), media_type: "text/plain"}
  end

  defp expected_facts(asset) do
    %{sha256: asset.sha256, byte_size: asset.byte_size, media_type: asset.media_type}
  end

  defp sealed_key(asset), do: "assets/sealed/#{asset.organization_id}/#{asset.sha256}"

  defp seed_asset(organization_id, overrides) do
    unique = System.unique_integer([:positive])

    defaults = %{
      organization_id: organization_id,
      state: "pending",
      sha256: Base.encode16(:crypto.hash(:sha256, "seed-#{unique}"), case: :lower),
      byte_size: 4,
      media_type: "text/plain",
      staging_key: "assets/staging/#{organization_id}/seed-#{unique}",
      staging_expires_at: DateTime.add(DateTime.utc_now(), -2, :hour)
    }

    Ash.Seed.seed!(Asset, Map.merge(defaults, overrides))
  end
end
