defmodule QuickTrain.Assets.AssetWorkersTest do
  use QuickTrain.DataCase, async: false
  use Oban.Testing, repo: QuickTrain.Repo

  alias QuickTrain.{Accounts, Assets, Datasets}
  alias QuickTrain.Assets.Asset
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

    assert :ok = perform_job(AssetStagingCleanup, %{})

    cleaned = Ash.get!(Asset, asset.id, authorize?: false)
    assert cleaned.state == "failed"
    assert cleaned.failure_reason == "staging_expired"
    assert %DateTime{} = cleaned.staging_cleaned_at
    assert is_nil(cleaned.operation_claim_id)

    assert :ok = perform_job(AssetStagingCleanup, %{})

    assert Ash.get!(Asset, asset.id, authorize?: false).staging_cleaned_at ==
             cleaned.staging_cleaned_at
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
end
