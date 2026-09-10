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

  test "claim transitions reject another owner or organization and publication rejects expiry", %{
    manager: manager,
    graph: graph
  } do
    registration =
      Assets.register_asset!(graph.organization.id, sha256("claim"), 5, "text/plain",
        actor: manager
      )

    claim_id = Ash.UUID.generate()
    expires_at = DateTime.add(DateTime.utc_now(), 60, :second)
    asset = Ash.get!(Asset, registration.asset.id, authorize?: false)

    asset =
      Ash.Seed.update!(asset, %{
        operation_claim_id: claim_id,
        operation_claim_expires_at: expires_at
      })

    opts = [authorize?: false, bulk_options: [strategy: [:atomic]]]

    for {organization_id, owner} <- [
          {graph.organization.id, Ash.UUID.generate()},
          {Ash.UUID.generate(), claim_id}
        ] do
      assert {:error, _} =
               Assets.start_asset_publication(
                 asset.id,
                 organization_id,
                 %{claim_id: owner, operation_claim_expires_at: expires_at},
                 opts
               )

      assert {:error, _} =
               Assets.release_asset_claim(asset.id, organization_id, %{claim_id: owner}, opts)
    end

    assert Ash.get!(Asset, asset.id, authorize?: false).operation_claim_id == claim_id

    assert {:ok, renewed} =
             Assets.start_asset_publication(
               asset.id,
               graph.organization.id,
               %{claim_id: claim_id, operation_claim_expires_at: expires_at},
               opts
             )

    expired =
      Ash.Seed.update!(renewed, %{
        operation_claim_expires_at: DateTime.add(DateTime.utc_now(), -1, :second)
      })

    assert {:error, _} =
             Assets.start_asset_publication(
               expired.id,
               graph.organization.id,
               %{claim_id: claim_id, operation_claim_expires_at: expires_at},
               opts
             )

    assert Ash.get!(Asset, asset.id, authorize?: false).operation_claim_expires_at ==
             expired.operation_claim_expires_at

    assert {:ok, released} =
             Assets.release_asset_claim(
               expired.id,
               graph.organization.id,
               %{claim_id: claim_id},
               opts
             )

    assert is_nil(released.operation_claim_id)
    assert is_nil(released.operation_claim_expires_at)
  end

  defp sha256(content),
    do: Base.encode16(:crypto.hash(:sha256, content), case: :lower)
end
