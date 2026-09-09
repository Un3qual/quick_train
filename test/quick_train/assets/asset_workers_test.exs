defmodule QuickTrain.Assets.AssetWorkersTest do
  use QuickTrain.DataCase, async: false
  use Oban.Testing, repo: QuickTrain.Repo

  alias QuickTrain.{Accounts, AshError, Assets}
  alias QuickTrain.Assets.Asset
  alias QuickTrain.Assets.Storage.InMemory, as: TestStorage
  alias QuickTrain.Assets.Workers.VerifyAsset

  setup do
    :ok = TestStorage.reset()

    manager = Accounts.register_user!("asset-worker@example.test", "Asset Worker")
    graph = organization_manager_fixture(manager.id, "asset-worker-org", "Asset Worker Org")

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
    assert Ash.get!(Asset, registration.asset.id, authorize?: false).state == :ready
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

    assert {:error, error} =
             perform_job(VerifyAsset, %{"asset_id" => registration.asset.id})

    assert AshError.reason?(error, :staging_missing)
    assert Ash.get!(Asset, registration.asset.id, authorize?: false).state == :pending
    :ok = TestStorage.put_staging(registration.upload_access, content)
    assert :ok = perform_job(VerifyAsset, %{"asset_id" => registration.asset.id})
    assert Ash.get!(Asset, registration.asset.id, authorize?: false).state == :ready
  end

  test "a publication that outlives its claim is adopted by a finalizer retry", %{
    manager: manager,
    graph: graph
  } do
    original_assets = Application.fetch_env!(:quick_train, :assets)

    test_assets =
      original_assets
      |> Keyword.put(:operation_claim_seconds, 1)

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

    assert {:error, error} =
             Assets.finalize_asset(registration.asset.id, graph.organization.id,
               authorize?: false
             )

    assert AshError.reason?(error, :stale_asset_claim)
    published_but_pending = Ash.get!(Asset, registration.asset.id, authorize?: false)
    assert published_but_pending.state == :pending
    assert TestStorage.sealed?("assets/sealed/#{graph.organization.id}/#{sha256(content)}")

    assert {:ok, result} =
             Assets.finalize_asset(published_but_pending.id, graph.organization.id,
               actor: manager
             )

    assert result.asset.state == :ready

    reconciled = Ash.get!(Asset, published_but_pending.id, authorize?: false)
    assert reconciled.state == :ready
    assert TestStorage.sealed?("assets/sealed/#{graph.organization.id}/#{sha256(content)}")
  end

  test "expired staging cannot be finalized", %{manager: manager, graph: graph} do
    registration =
      Assets.register_asset!(graph.organization.id, sha256("expired"), 7, "text/plain",
        actor: manager
      )

    asset = Ash.get!(Asset, registration.asset.id, authorize?: false)
    Ash.Seed.update!(asset, %{staging_expires_at: DateTime.add(DateTime.utc_now(), -1, :second)})

    result = Assets.finalize_asset!(asset.id, graph.organization.id, actor: manager)
    assert result.asset.state == :failed
    assert result.asset.failure_reason == "staging_expired"
    assert TestStorage.sealed_count() == 0
  end

  defp sha256(content),
    do: Base.encode16(:crypto.hash(:sha256, content), case: :lower)
end
