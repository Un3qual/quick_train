defmodule QuickTrain.Assets.AssetLifecycleTest do
  use QuickTrain.DataCase, async: false

  alias QuickTrain.{Accounts, Assets, Organizations}
  alias QuickTrain.Assets.Asset
  alias QuickTrain.Assets.Storage.InMemory, as: TestStorage

  defmodule InvalidUploadStorage do
    def enforces_byte_cap?, do: true
    def approved_hosts, do: ["storage.quicktrain.local"]

    def writable_staging_access(_key, cap, expiry) do
      {:ok,
       %{
         method: :put,
         uri: URI.parse("https://storage.quicktrain.local/upload"),
         max_bytes: cap,
         expires_at: expiry,
         cache_control: "no-store",
         referrer_policy: "no-referrer",
         headers: [42]
       }}
    end
  end

  defmodule InvalidPublicationStorage do
    def verify_and_publish(_staging_key, sealed_key, expected, _deadline) do
      case Process.get(:publication_fault) do
        :missing_key -> {:ok, %{facts: expected}}
        :wrong_key -> {:ok, %{sealed_key: "wrong", facts: expected}}
        :wrong_facts -> {:ok, %{sealed_key: sealed_key, facts: %{expected | byte_size: 0}}}
      end
    end
  end

  setup do
    :ok = TestStorage.reset()

    manager = Accounts.register_user!("asset-manager@example.test", "Asset Manager")
    graph = organization_manager_fixture(manager.id, "asset-org", "Asset Org")

    outsider = Accounts.register_user!("asset-outsider@example.test", "Asset Outsider")

    %{manager: manager, graph: graph, outsider: outsider}
  end

  test "authorized registration returns capped staging access and rejects oversized declarations",
       %{
         manager: manager,
         graph: graph,
         outsider: outsider
       } do
    content = "training asset"

    assert {:ok, registration} =
             Assets.register_asset(
               graph.organization.id,
               sha256(content),
               byte_size(content),
               "text/plain",
               actor: manager
             )

    assert registration.asset.organization_id == graph.organization.id
    assert registration.asset.state == :pending
    assert registration.asset.sha256 == :crypto.hash(:sha256, content)

    assert Ash.get!(Asset, registration.asset.id, authorize?: false).sha256 ==
             registration.asset.sha256

    assert registration.upload_access.max_bytes == byte_size(content)
    refute Map.has_key?(registration, :staging_key)

    assert {:error, %Ash.Error.Forbidden{}} =
             Assets.register_asset(
               graph.organization.id,
               sha256(content),
               byte_size(content),
               "text/plain",
               actor: outsider
             )

    max_bytes = Application.fetch_env!(:quick_train, :assets)[:max_bytes]

    assert {:error, oversized_error} =
             Assets.register_asset(
               graph.organization.id,
               String.duplicate("0", 64),
               max_bytes + 1,
               "text/plain",
               actor: manager
             )

    assert Exception.message(oversized_error) =~ "asset_too_large"
    assert Ash.count!(Asset, authorize?: false) == 1
  end

  test "malformed upload headers leave no pending registration", %{manager: manager, graph: graph} do
    config = Application.fetch_env!(:quick_train, :assets)
    on_exit(fn -> Application.put_env(:quick_train, :assets, config) end)

    Application.put_env(
      :quick_train,
      :assets,
      Keyword.put(config, :storage_adapter, InvalidUploadStorage)
    )

    assert {:error, error} =
             Assets.register_asset(
               graph.organization.id,
               sha256("content"),
               7,
               "text/plain",
               actor: manager
             )

    assert Exception.message(error) =~ "invalid_storage_descriptor"
    assert Ash.count!(Asset, authorize?: false) == 0
  end

  test "matching staging finalizes immutably and returns only sealed read access", %{
    manager: manager,
    graph: graph
  } do
    content = "ready asset"
    registration = register!(graph.organization.id, manager, content, "text/plain")
    :ok = TestStorage.put_staging(registration.upload_access, content)

    assert {:ok, finalized} =
             Assets.finalize_asset(
               registration.asset.id,
               graph.organization.id,
               actor: manager
             )

    assert finalized.asset.state == :ready
    assert finalized.canonical_asset.id == finalized.asset.id

    assert {:ok, access} =
             Assets.get_asset_access(
               finalized.asset.id,
               graph.organization.id,
               actor: manager
             )

    assert access.asset.id == finalized.asset.id
    assert access.read_access.method == :get
    assert {:ok, ^content} = TestStorage.read_sealed(access.read_access)

    assert_raise ArgumentError, ~r/No such update action/, fn ->
      stored_asset = Ash.get!(Asset, finalized.asset.id, authorize?: false)
      Ash.Changeset.for_update(stored_asset, :update, %{media_type: "application/pdf"})
    end
  end

  test "invalid publication success never marks an asset ready", %{manager: actor, graph: graph} do
    config = Application.fetch_env!(:quick_train, :assets)
    on_exit(fn -> Application.put_env(:quick_train, :assets, config) end)

    for fault <- [:missing_key, :wrong_key, :wrong_facts] do
      Application.put_env(:quick_train, :assets, config)
      registration = register!(graph.organization.id, actor, "bytes", "text/plain")

      Application.put_env(
        :quick_train,
        :assets,
        Keyword.put(config, :storage_adapter, InvalidPublicationStorage)
      )

      Process.put(:publication_fault, fault)

      assert {:error, error} =
               Assets.finalize_asset(registration.asset.id, graph.organization.id, actor: actor)

      assert Exception.message(error) =~ "invalid_storage_result"
      asset = Ash.get!(Asset, registration.asset.id, authorize?: false)
      assert asset.state == :pending
      assert is_nil(asset.sealed_key)
    end

    assert TestStorage.sealed_count() == 0
  end

  test "mismatched bytes become a sanitized failure without canonical publication", %{
    manager: manager,
    graph: graph
  } do
    registration = register!(graph.organization.id, manager, "expected", "text/plain")
    :ok = TestStorage.put_staging(registration.upload_access, "differnt")

    assert {:ok, finalized} =
             Assets.finalize_asset(
               registration.asset.id,
               graph.organization.id,
               actor: manager
             )

    assert finalized.asset.state == :failed
    assert finalized.asset.failure_reason == "content_mismatch"
    assert is_nil(finalized.canonical_asset)
    assert TestStorage.sealed_count() == 0
  end

  test "existing canonical content cannot hide a mismatched staging upload", %{
    manager: manager,
    graph: graph
  } do
    first = register!(graph.organization.id, manager, "expected", "text/plain")
    second = register!(graph.organization.id, manager, "expected", "text/plain")
    :ok = TestStorage.put_staging(first.upload_access, "expected")
    :ok = TestStorage.put_staging(second.upload_access, "differnt")

    assert Assets.finalize_asset!(first.asset.id, graph.organization.id, actor: manager).asset.state ==
             :ready

    rejected = Assets.finalize_asset!(second.asset.id, graph.organization.id, actor: manager)
    assert rejected.asset.state == :failed
    assert rejected.asset.failure_reason == "content_mismatch"
    assert is_nil(rejected.canonical_asset)
    assert TestStorage.sealed_count() == 1
  end

  test "a staging overwrite racing finalization can never change ready bytes", %{
    manager: manager,
    graph: graph
  } do
    original = "original-bytes"
    replacement = "replaced-bytes"
    registration = register!(graph.organization.id, manager, original, "text/plain")
    :ok = TestStorage.put_staging(registration.upload_access, original)
    :ok = TestStorage.set_publish_delay(100)

    finalization =
      Task.async(fn ->
        Assets.finalize_asset!(registration.asset.id, graph.organization.id, actor: manager)
      end)

    overwrite_result = TestStorage.put_staging(registration.upload_access, replacement)
    finalized = Task.await(finalization)

    case overwrite_result do
      :ok ->
        assert finalized.asset.state == :failed
        assert finalized.asset.failure_reason == "content_mismatch"
        assert TestStorage.sealed_count() == 0

      {:error, :staging_fenced} ->
        assert finalized.asset.state == :ready

        access =
          Assets.get_asset_access!(finalized.asset.id, graph.organization.id, actor: manager)

        assert {:ok, ^original} = TestStorage.read_sealed(access.read_access)
    end
  end

  @tag :committed_db
  test "concurrent-ready content converges and matching registration reuses the canonical asset",
       %{
         manager: manager,
         graph: graph
       } do
    content = "same immutable bytes"
    first = register!(graph.organization.id, manager, content, "text/plain")
    second = register!(graph.organization.id, manager, content, "text/plain")
    :ok = TestStorage.put_staging(first.upload_access, content)
    :ok = TestStorage.put_staging(second.upload_access, content)

    [first_result, second_result] =
      concurrently(
        for asset_id <- [first.asset.id, second.asset.id] do
          fn -> Assets.finalize_asset!(asset_id, graph.organization.id, actor: manager) end
        end
      )

    [ready_result] = Enum.filter([first_result, second_result], &(&1.asset.state == :ready))

    [duplicate_result] =
      Enum.filter([first_result, second_result], &(&1.asset.state == :duplicate_content))

    assert duplicate_result.asset.canonical_asset_id == ready_result.asset.id
    assert duplicate_result.canonical_asset.id == ready_result.asset.id
    assert TestStorage.sealed_count() == 1

    assert {:ok, reused} =
             Assets.register_asset(
               graph.organization.id,
               sha256(content),
               byte_size(content),
               "text/plain",
               actor: manager
             )

    assert reused.reused
    assert reused.asset.id == ready_result.asset.id
    assert is_nil(reused.upload_access)
    assert Ash.count!(Asset, authorize?: false) == 2

    assert {:error, conflict} =
             Assets.register_asset(
               graph.organization.id,
               sha256(content),
               byte_size(content) + 1,
               "text/plain",
               actor: manager
             )

    assert Exception.message(conflict) =~ "asset_identity_conflict"
  end

  @tag :committed_db
  test "conflicting declared media types terminate without retaining a claim", %{
    manager: manager,
    graph: graph
  } do
    content = "same opaque bytes"

    registrations =
      for media_type <- ["text/plain", "application/octet-stream"] do
        registration = register!(graph.organization.id, manager, content, media_type)
        :ok = TestStorage.put_staging(registration.upload_access, content)
        registration
      end

    results =
      concurrently(
        for registration <- registrations do
          fn ->
            Assets.finalize_asset!(registration.asset.id, graph.organization.id, actor: manager)
          end
        end
      )

    assert Enum.count(results, &(&1.asset.state == :ready)) == 1
    [failed] = Enum.filter(results, &(&1.asset.state == :failed))
    assert failed.asset.failure_reason == "asset_identity_conflict"
    stored = Ash.get!(Asset, failed.asset.id, authorize?: false)
    assert is_nil(stored.operation_claim_id)
    assert is_nil(stored.operation_claim_expires_at)
    retry = Assets.finalize_asset!(stored.id, graph.organization.id, actor: manager)
    assert retry.asset.state == :failed
    assert retry.asset.failure_reason == "asset_identity_conflict"
    assert TestStorage.sealed_count() == 1
  end

  test "asset hashes must be supplied without surrounding whitespace", %{
    manager: actor,
    graph: graph
  } do
    for hash <- [" " <> sha256("bytes"), sha256("bytes") <> "\n"] do
      assert {:error, error} =
               Assets.register_asset(graph.organization.id, hash, 5, "text/plain", actor: actor)

      assert Exception.message(error) =~ "invalid_asset_hash"
    end

    assert Ash.count!(Asset, authorize?: false) == 0
  end

  test "invalid media text is rejected before requesting storage access", %{
    manager: manager,
    graph: graph
  } do
    config = Application.fetch_env!(:quick_train, :assets)
    on_exit(fn -> Application.put_env(:quick_train, :assets, config) end)
    Application.put_env(:quick_train, :assets, Keyword.delete(config, :storage_adapter))

    assert {:error, error} =
             Assets.register_asset(
               graph.organization.id,
               sha256("bytes"),
               5,
               "text/plain" <> <<0>>,
               actor: manager
             )

    assert Exception.message(error) =~ "invalid_media_type"
    assert Ash.count!(Asset, authorize?: false) == 0
  end

  test "asset actions require the explicit owning organization", %{
    manager: manager,
    graph: graph
  } do
    content = "private asset"
    registration = register!(graph.organization.id, manager, content, "text/plain")
    :ok = TestStorage.put_staging(registration.upload_access, content)

    finalized =
      Assets.finalize_asset!(registration.asset.id, graph.organization.id, actor: manager)

    other = Organizations.create_organization!("Other Asset Org", "other-asset-org")
    Organizations.add_member!(other.id, manager.id)

    assert {:error, %Ash.Error.Forbidden{}} =
             Assets.get_asset_access(finalized.asset.id, other.id, actor: manager)

    assert {:error, %Ash.Error.Forbidden{}} =
             Assets.finalize_asset(finalized.asset.id, other.id, actor: manager)
  end

  defp register!(organization_id, actor, content, media_type) do
    Assets.register_asset!(
      organization_id,
      sha256(content),
      byte_size(content),
      media_type,
      actor: actor
    )
  end

  defp sha256(content),
    do: Base.encode16(:crypto.hash(:sha256, content), case: :lower)
end
