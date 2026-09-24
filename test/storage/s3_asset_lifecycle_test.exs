defmodule QuickTrain.Assets.S3AssetLifecycleTest do
  use QuickTrain.DataCase, async: false
  import SweetXml, only: [sigil_x: 2]

  alias QuickTrain.{Accounts, AshError, Assets}
  alias QuickTrain.Assets.Asset
  alias QuickTrain.Assets.Storage.S3
  alias QuickTrainWeb.S3FaultServer, as: Server

  @moduletag :storage
  @moduletag :committed_db

  setup_all do
    QuickTrain.S3Fixture.configure()
  end

  setup do
    QuickTrain.S3Fixture.use_adapter()
    suffix = Ash.UUID.generate()
    manager = Accounts.register_user!("s3-assets-#{suffix}@example.test", "Asset Manager")
    graph = organization_manager_fixture(manager.id, "s3-assets-#{suffix}", "S3 Assets")
    options = Application.fetch_env!(:quick_train, :s3_storage)
    on_exit(fn -> Application.put_env(:quick_train, :s3_storage, options) end)
    %{manager: manager, organization_id: graph.organization.id, options: options}
  end

  test "racing identical registrations publish one version and converge to ready and duplicate",
       ctx do
    content = "concurrent immutable bytes"
    media_type = String.duplicate("音声", 2000)
    first = register_and_stage!(ctx, content, media_type)
    second = register_and_stage!(ctx, content, media_type)
    refute first.id == second.id
    canonical_key = canonical_key(ctx, content)
    pause_publication(ctx, canonical_key)

    operation =
      Task.async(fn ->
        concurrently(
          for asset <- [first, second] do
            fn -> Assets.finalize_asset!(asset.id, ctx.organization_id, actor: ctx.manager) end
          end
        )
      end)

    try do
      assert_receive {:canonical_waiting, first_request}, 5_000
      assert_receive {:canonical_waiting, second_request}, 5_000
      send(first_request, :publish)
      send(second_request, :publish)
      results = Task.await(operation, 15_000)

      assert_receive {:canonical_response, first_status}, 5_000
      assert_receive {:canonical_response, second_status}, 5_000
      assert Enum.sort([first_status, second_status]) == [200, 412]

      [ready] = Enum.filter(results, &(&1.asset.state == :ready))
      [duplicate] = Enum.filter(results, &(&1.asset.state == :duplicate_content))
      assert duplicate.asset.canonical_asset_id == ready.asset.id
      assert duplicate.canonical_asset.id == ready.asset.id
      assert ready.asset.media_type == media_type
      assert Ash.get!(Asset, ready.asset.id, authorize?: false).state == :ready
      assert Ash.get!(Asset, duplicate.asset.id, authorize?: false).state == :duplicate_content
      assert [%{key: ^canonical_key, is_latest: "true"}] = versions(ctx, canonical_key)
      assert object(ctx, canonical_key).body == content

      reused =
        Assets.register_asset!(
          ctx.organization_id,
          sha256(content),
          byte_size(content),
          media_type,
          actor: ctx.manager
        )

      assert reused.reused
      assert reused.asset.id == ready.asset.id
      assert reused.asset.media_type == media_type
      assert is_nil(reused.upload_access)
      assert Ash.count!(Asset, authorize?: false) == 2
    after
      Task.shutdown(operation, :brutal_kill)
    end
  end

  test "publication under an expired claim stays pending until a current retry adopts it", ctx do
    content = "published after claim expiry"
    asset = register_and_stage!(ctx, content, "text/plain")
    canonical_key = canonical_key(ctx, content)
    pause_publication(ctx, canonical_key)

    operation =
      Task.async(fn ->
        concurrently([
          fn -> Assets.finalize_asset(asset.id, ctx.organization_id, actor: ctx.manager) end
        ])
      end)

    try do
      assert_receive {:canonical_waiting, request}, 5_000
      claimed = Ash.get!(Asset, asset.id, authorize?: false)
      refute is_nil(claimed.operation_claim_id)

      claimed
      |> Ash.Changeset.for_update(:claim_operation, %{
        operation_claim_expires_at: DateTime.add(DateTime.utc_now(), -1, :second)
      })
      |> Ash.update!(authorize?: false)

      send(request, :publish)
      assert [{:error, error}] = Task.await(operation, 15_000)
      assert AshError.reason?(error, :stale_asset_claim)
      assert_receive {:canonical_response, 200}, 5_000

      pending = Ash.get!(Asset, asset.id, authorize?: false)
      assert pending.state == :pending
      assert is_nil(pending.sealed_key)
      assert pending.operation_claim_id == claimed.operation_claim_id
      assert pending.staging_expires_at == asset.staging_expires_at
      assert object(ctx, canonical_key).body == content
      assert [published_version] = versions(ctx, canonical_key)

      Application.put_env(:quick_train, :s3_storage, ctx.options)
      finalized = Assets.finalize_asset!(asset.id, ctx.organization_id, actor: ctx.manager)
      assert finalized.asset.id == asset.id
      assert finalized.asset.state == :ready
      assert finalized.canonical_asset.id == asset.id
      assert versions(ctx, canonical_key) == [published_version]

      ready = Ash.get!(Asset, asset.id, authorize?: false)
      assert ready.state == :ready
      assert ready.staging_expires_at == asset.staging_expires_at
      assert is_nil(ready.operation_claim_id)
      assert is_nil(ready.operation_claim_expires_at)
    after
      Task.shutdown(operation, :brutal_kill)
    end
  end

  test "conflicting canonical media facts fail the pending identity without replacing bytes",
       ctx do
    content = "same bytes with different declared media"
    first = register_and_stage!(ctx, content, "text/plain")
    second = register_and_stage!(ctx, content, "application/octet-stream")
    canonical_key = canonical_key(ctx, content)
    ready = Assets.finalize_asset!(first.id, ctx.organization_id, actor: ctx.manager)
    assert ready.asset.state == :ready
    assert [original_version] = versions(ctx, canonical_key)

    failed = Assets.finalize_asset!(second.id, ctx.organization_id, actor: ctx.manager)
    assert failed.asset.id == second.id
    assert failed.asset.state == :failed
    assert failed.asset.failure_reason == "asset_identity_conflict"
    assert is_nil(failed.canonical_asset)
    stored = Ash.get!(Asset, second.id, authorize?: false)
    assert stored.state == :failed
    assert is_nil(stored.sealed_key)
    assert is_nil(stored.operation_claim_id)
    assert is_nil(stored.operation_claim_expires_at)
    assert Ash.get!(Asset, first.id, authorize?: false).state == :ready
    assert versions(ctx, canonical_key) == [original_version]
    response = object(ctx, canonical_key)
    assert response.body == content

    assert {"x-amz-meta-declared-media-type-sha256", sha256("text/plain")} in response.headers

    retry = Assets.finalize_asset!(second.id, ctx.organization_id, actor: ctx.manager)
    assert retry.asset.state == :failed
    assert retry.asset.failure_reason == "asset_identity_conflict"
    assert versions(ctx, canonical_key) == [original_version]
  end

  test "a lost canonical PUT response leaves pending content for a current claim to reverify",
       ctx do
    content = "canonical bytes whose response is lost"
    asset = register_and_stage!(ctx, content, "text/plain")
    canonical_key = canonical_key(ctx, content)
    path = "/#{ctx.s3_config.bucket}/#{canonical_key}"
    parent = self()
    assets = Application.fetch_env!(:quick_train, :assets)
    on_exit(fn -> Application.put_env(:quick_train, :assets, assets) end)

    endpoint =
      Server.start(fn conn ->
        result = Server.forward(conn, ctx.options[:endpoint])

        if conn.method == "PUT" and conn.request_path == path do
          send(parent, {:canonical_committed, self(), elem(result, 1).status})

          receive do
            :release_response -> :ok
          after
            5_000 -> raise "canonical response barrier timed out"
          end
        end

        Server.respond(result)
      end)

    Application.put_env(:quick_train, :s3_storage, Keyword.put(ctx.options, :endpoint, endpoint))
    Application.put_env(:quick_train, :assets, Keyword.put(assets, :publication_deadline_ms, 500))
    started = System.monotonic_time(:millisecond)

    operation =
      Task.async(fn ->
        concurrently([
          fn -> Assets.finalize_asset(asset.id, ctx.organization_id, actor: ctx.manager) end
        ])
      end)

    try do
      assert_receive {:canonical_committed, response_holder, 200}, 2_000
      assert [{:error, error}] = Task.await(operation, 2_000)
      assert AshError.reason?(error, :storage_deadline_exceeded)
      assert System.monotonic_time(:millisecond) - started < 2_000

      pending = Ash.get!(Asset, asset.id, authorize?: false)
      assert pending.state == :pending
      assert is_nil(pending.sealed_key)
      refute is_nil(pending.operation_claim_id)
      assert pending.staging_expires_at == asset.staging_expires_at
      assert object(ctx, canonical_key).body == content
      assert [committed_version] = versions(ctx, canonical_key)

      assert {:error, denied} =
               Assets.get_asset_access(asset.id, ctx.organization_id, actor: ctx.manager)

      assert AshError.reason?(denied, :asset_not_ready)
      send(response_holder, :release_response)

      pending
      |> Ash.Changeset.for_update(:claim_operation, %{
        operation_claim_expires_at: DateTime.add(DateTime.utc_now(), -1, :second)
      })
      |> Ash.update!(authorize?: false)

      Application.put_env(:quick_train, :s3_storage, ctx.options)
      Application.put_env(:quick_train, :assets, assets)
      finalized = Assets.finalize_asset!(asset.id, ctx.organization_id, actor: ctx.manager)
      assert finalized.asset.id == asset.id
      assert finalized.asset.state == :ready
      assert versions(ctx, canonical_key) == [committed_version]

      access = Assets.get_asset_access!(asset.id, ctx.organization_id, actor: ctx.manager)
      assert Req.get!(ctx.request, url: access.read_access.uri).body == content
      ready = Ash.get!(Asset, asset.id, authorize?: false)
      assert is_nil(ready.operation_claim_id)
      assert ready.staging_expires_at == asset.staging_expires_at
    after
      Task.shutdown(operation, :brutal_kill)
    end
  end

  test "temporary verification GET failures retain the pending identity for retry", ctx do
    for stage <- [:staging, :sealed] do
      Application.put_env(:quick_train, :s3_storage, ctx.options)
      content = "retry after #{stage} GET failure"
      asset = register_and_stage!(ctx, content, "text/plain")
      canonical_key = canonical_key(ctx, content)
      failed_key = if stage == :staging, do: asset.staging_key, else: canonical_key
      path = "/#{ctx.s3_config.bucket}/#{failed_key}"

      endpoint =
        Server.start(fn conn ->
          if conn.method == "GET" and conn.request_path == path do
            Plug.Conn.send_resp(conn, 503, "temporary provider failure")
          else
            conn |> Server.forward(ctx.options[:endpoint]) |> Server.respond()
          end
        end)

      Application.put_env(
        :quick_train,
        :s3_storage,
        Keyword.put(ctx.options, :endpoint, endpoint)
      )

      assert {:error, error} =
               Assets.finalize_asset(asset.id, ctx.organization_id, actor: ctx.manager)

      assert AshError.reason?(error, :storage_request_failed)
      pending = Ash.get!(Asset, asset.id, authorize?: false)
      assert pending.state == :pending
      assert is_nil(pending.sealed_key)
      assert pending.staging_expires_at == asset.staging_expires_at
      previous_versions = versions(ctx, canonical_key)
      assert length(previous_versions) == if(stage == :sealed, do: 1, else: 0)

      pending
      |> Ash.Changeset.for_update(:claim_operation, %{
        operation_claim_expires_at: DateTime.add(DateTime.utc_now(), -1, :second)
      })
      |> Ash.update!(authorize?: false)

      Application.put_env(:quick_train, :s3_storage, ctx.options)
      finalized = Assets.finalize_asset!(asset.id, ctx.organization_id, actor: ctx.manager)
      assert finalized.asset.id == asset.id
      assert finalized.asset.state == :ready
      assert [published] = versions(ctx, canonical_key)
      if stage == :sealed, do: assert(previous_versions == [published])
      assert object(ctx, canonical_key).body == content
    end
  end

  defp register_and_stage!(ctx, content, media_type) do
    registration =
      Assets.register_asset!(ctx.organization_id, sha256(content), byte_size(content), media_type,
        actor: ctx.manager
      )

    asset = Ash.get!(Asset, registration.asset.id, authorize?: false)
    assert :ok = S3.write_staging(asset.staging_key, [content], byte_size(content), 5_000)
    asset
  end

  defp pause_publication(ctx, canonical_key) do
    parent = self()
    path = "/#{ctx.s3_config.bucket}/#{canonical_key}"

    endpoint =
      Server.start(fn conn ->
        if conn.method == "PUT" and conn.request_path == path do
          send(parent, {:canonical_waiting, self()})

          receive do
            :publish -> :ok
          after
            10_000 -> raise "canonical publication barrier timed out"
          end

          result = Server.forward(conn, ctx.options[:endpoint])
          send(parent, {:canonical_response, elem(result, 1).status})
          Server.respond(result)
        else
          conn |> Server.forward(ctx.options[:endpoint]) |> Server.respond()
        end
      end)

    Application.put_env(:quick_train, :s3_storage, Keyword.put(ctx.options, :endpoint, endpoint))
  end

  defp object(ctx, key) do
    {:ok, response} =
      ExAws.Operation.perform(ExAws.S3.get_object(ctx.s3_config.bucket, key), ctx.s3_config.sdk)

    response
  end

  defp versions(ctx, key) do
    operation = ExAws.S3.list_object_versions(ctx.s3_config.bucket, prefix: key)

    {:ok, response} =
      ExAws.Operation.perform(%{operation | parser: &Function.identity/1}, ctx.s3_config.sdk)

    # The SDK's default version parser requires Owner, which VersityGW omits.
    assert SweetXml.xpath(response.body, ~x"/ListVersionsResult/IsTruncated/text()"s) == "false"

    SweetXml.xpath(response.body, ~x"/ListVersionsResult/Version"l,
      key: ~x"./Key/text()"s,
      version_id: ~x"./VersionId/text()"s,
      is_latest: ~x"./IsLatest/text()"s
    )
  end

  defp canonical_key(ctx, content), do: "assets/sealed/#{ctx.organization_id}/#{sha256(content)}"
  defp sha256(content), do: Base.encode16(:crypto.hash(:sha256, content), case: :lower)
end
