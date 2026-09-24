defmodule QuickTrain.Storage.S3ExportTest do
  use QuickTrain.ConnCase, async: false

  alias QuickTrain.{Accounts, Authorization, Organizations, ProjectsFixture, Tasks}
  alias QuickTrain.Assets.Asset
  alias QuickTrain.Assets.Storage.S3
  alias QuickTrain.Tasks.Exports.ResultExport
  alias QuickTrainWeb.S3FaultServer, as: Server

  @moduletag :storage
  @moduletag :committed_db

  setup_all do
    QuickTrain.S3Fixture.configure()
  end

  setup do
    QuickTrain.S3Fixture.use_adapter()
    context = ProjectsFixture.context!()
    source = ProjectsFixture.source!(context)

    project =
      ProjectsFixture.active!(context, source, audience: :external_users, external_access: :open)

    worker = Accounts.register_user!("s3-export-worker@example.test", "Worker")
    reader = result_reader!(context)
    outsider = ProjectsFixture.context!(~w(tasks.results.read), "s3-export-outsider").actor

    %{
      context: context,
      source: source,
      project: project,
      worker: worker,
      reader: reader,
      outsider: outsider
    }
  end

  test "a result-only reader downloads the sealed snapshot through real private storage", ctx do
    first = submit!(ctx, 4)
    conn = bearer(ctx.conn, ctx.reader)

    requested =
      graphql!(conn, """
      mutation {
        requestResultExport(input: {#{scope(ctx)}, requestKey: "#{Ash.UUID.generate()}", mode: "audit"}) {
          result { id state } errors { message }
        }
      }
      """)["requestResultExport"]

    assert requested["errors"] == []
    export_id = requested["result"]["id"]
    sealed = Tasks.seal_export_snapshot!(export_id, authorize?: false)
    assert sealed.record_count == 1

    second = submit!(ctx, 2)
    assert second.id != first.id
    assert :ok = Tasks.process_result_export(export_id, authorize?: false)

    status =
      graphql!(conn, """
      { resultExport(#{scope(ctx)}, exportId: "#{export_id}") { state recordCount snapshotAt } }
      """)["resultExport"]

    assert status["state"] == "ready"
    assert status["recordCount"] == "1"
    assert status["snapshotAt"] == DateTime.to_iso8601(sealed.snapshot_at)

    query = """
    { resultExportDownload(#{scope(ctx)}, exportId: "#{export_id}") {
      asset { id sha256 byteSize mediaType }
      readAccess { method uri headers expiresAt cacheControl referrerPolicy formFields fileField }
    } }
    """

    access = graphql!(conn, query)["resultExportDownload"]
    descriptor = access["readAccess"]
    assert descriptor["method"] == "GET"
    assert descriptor["cacheControl"] == "no-store"
    assert descriptor["referrerPolicy"] == "no-referrer"
    assert is_nil(descriptor["formFields"])
    assert is_nil(descriptor["fileField"])
    assert access["asset"]["mediaType"] == "application/x-ndjson"

    response = download!(ctx, descriptor)
    assert response.status == 200
    assert Req.Response.get_header(response, "content-disposition") == ["attachment"]
    assert Req.Response.get_header(response, "content-type") == ["application/octet-stream"]
    assert Req.Response.get_header(response, "cache-control") == ["no-store"]
    assert access["asset"]["byteSize"] == byte_size(response.body)

    assert access["asset"]["sha256"] ==
             Base.encode16(:crypto.hash(:sha256, response.body), case: :lower)

    assert [header, result] =
             response.body |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)

    assert header["kind"] == "header"
    assert header["format_version"] == 1
    assert header["record_count"] == "1"
    assert header["snapshot_at"] == DateTime.to_iso8601(sealed.snapshot_at)
    assert header["organization_id"] == ctx.context.org.id
    assert header["project_id"] == ctx.project.id
    assert result["kind"] == "result"
    assert result["attempt_id"] == first.id
    assert result["question_id"] == ctx.source.form.question.id
    assert result["integer_value"] == 4

    assert [%{"values" => [%{"field_key" => "body", "text_value" => "Body 1"}]}] =
             result["inputs"]

    assert :ok = Tasks.process_result_export(export_id, authorize?: false)
    repeated = graphql!(conn, query)["resultExportDownload"]
    assert repeated["asset"]["id"] == access["asset"]["id"]
    assert download!(ctx, repeated["readAccess"]).body == response.body
    assert Ash.get!(ResultExport, export_id, authorize?: false).snapshot_at == sealed.snapshot_at

    denied = request(bearer(ctx.conn, ctx.outsider), query)
    assert [%{"message" => _} | _] = denied["errors"]
    assert is_nil(denied["data"]["resultExportDownload"])

    ordinary_access = """
    { assetAccess(organizationId: "#{ctx.context.org.id}", assetId: "#{access["asset"]["id"]}") {
      readAccess { uri }
    } }
    """

    assert [%{"message" => _} | _] = request(conn, ordinary_access)["errors"]
  end

  test "a timed-out export retains its snapshot and pending identity when remote bytes arrive later",
       ctx do
    first = submit!(ctx, 4)

    export =
      Tasks.request_result_export!(
        ctx.context.org.id,
        ctx.project.id,
        Ash.UUID.generate(),
        :audit,
        actor: ctx.reader
      )

    snapshot = Tasks.seal_export_snapshot!(export.id, authorize?: false)
    {:ok, storage} = S3.Config.fetch()
    options = Application.fetch_env!(:quick_train, :s3_storage)
    assets = Application.fetch_env!(:quick_train, :assets)

    on_exit(fn ->
      Application.put_env(:quick_train, :s3_storage, options)
      Application.put_env(:quick_train, :assets, assets)
    end)

    parent = self()

    endpoint =
      Server.start(fn conn ->
        send(parent, {:remote_waiting, self(), conn.method, conn.request_path})

        receive do
          :finish_remote -> :ok
        after
          5_000 -> raise "test barrier timed out"
        end

        result = Server.forward(conn, options[:endpoint])
        send(parent, {:remote_finished, elem(result, 1).status})
        Server.respond(result)
      end)

    Application.put_env(:quick_train, :s3_storage, Keyword.put(options, :endpoint, endpoint))
    Application.put_env(:quick_train, :assets, Keyword.put(assets, :publication_deadline_ms, 250))
    started = System.monotonic_time(:millisecond)
    operation = Task.async(fn -> Tasks.process_result_export(export.id, authorize?: false) end)
    assert_receive {:remote_waiting, server, "PUT", path}, 2_000
    on_exit(fn -> send(server, :finish_remote) end)

    assert {:error,
            %Ash.Error.Invalid{
              errors: [%QuickTrain.DatasetAssetError{category: :storage_deadline_exceeded}]
            }} = Task.await(operation, 2_000)

    assert System.monotonic_time(:millisecond) - started < 2_000
    failed = Ash.get!(ResultExport, export.id, authorize?: false)
    pending = Ash.get!(Asset, failed.pending_asset_id, authorize?: false)
    assert path == "/#{storage.bucket}/#{pending.staging_key}"
    assert failed.state == :failed
    assert failed.error_code == "storage_deadline_exceeded"
    assert is_nil(failed.asset_id)
    assert failed.snapshot_at == snapshot.snapshot_at
    assert failed.record_count == snapshot.record_count
    assert pending.state == :pending
    assert pending.result_export_id == export.id
    assert is_nil(pending.sealed_key)
    assert is_nil(pending.operation_claim_id)
    assert DateTime.after?(pending.staging_expires_at, DateTime.utc_now())
    assert staging_read!(ctx.request, storage, pending).status == 404

    assert Path.wildcard(Path.join(System.tmp_dir!(), "quick_train_export_#{export.id}_*.jsonl")) ==
             []

    send(server, :finish_remote)
    assert_receive {:remote_finished, 200}, 2_000
    remote = staging_read!(ctx.request, storage, pending)
    assert remote.status == 200
    assert byte_size(remote.body) == pending.byte_size
    assert :crypto.hash(:sha256, remote.body) == pending.sha256

    # Complete private bytes do not establish either asset or export readiness.
    assert Ash.get!(Asset, pending.id, authorize?: false).state == :pending
    assert Ash.get!(ResultExport, export.id, authorize?: false).state == :failed

    assert {:error, error} =
             Tasks.result_export_download(ctx.context.org.id, ctx.project.id, export.id,
               actor: ctx.reader
             )

    assert Exception.message(error) =~ "export_not_ready"

    Application.put_env(:quick_train, :s3_storage, options)
    Application.put_env(:quick_train, :assets, assets)
    submit!(ctx, 2)
    assert :ok = Tasks.process_result_export(export.id, authorize?: false)
    ready = Ash.get!(ResultExport, export.id, authorize?: false)
    asset = Ash.get!(Asset, ready.asset_id, authorize?: false)
    assert ready.state == :ready
    assert ready.pending_asset_id == pending.id
    assert ready.asset_id == pending.id
    assert ready.snapshot_at == snapshot.snapshot_at
    assert ready.record_count == 1
    assert asset.state == :ready
    assert asset.staging_expires_at == pending.staging_expires_at

    access =
      Tasks.result_export_download!(ctx.context.org.id, ctx.project.id, export.id,
        actor: ctx.reader
      )

    response = Req.get!(ctx.request, url: access.read_access.uri)
    assert response.status == 200
    assert response.body == remote.body

    assert [_header, %{"attempt_id" => attempt_id, "integer_value" => 4}] =
             response.body |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)

    assert attempt_id == first.id
  end

  defp staging_read!(request, storage, asset) do
    {:ok, uri} =
      ExAws.S3.presigned_url(storage.sdk, :get, storage.bucket, asset.staging_key, expires_in: 60)

    Req.get!(request, url: uri)
  end

  defp submit!(ctx, value) do
    attempt =
      Tasks.fetch_work!(ctx.context.org.id, ctx.project.id, Ash.UUID.generate(),
        actor: ctx.worker
      ).attempt

    Tasks.save_question!(
      attempt,
      %{
        question_id: ctx.source.form.question.id,
        expected_revision: 0,
        answer: %{outcome: :answered, family: :integer, integer_value: value}
      },
      actor: ctx.worker
    )

    Tasks.submit_response!(attempt, actor: ctx.worker)
    attempt
  end

  defp result_reader!(context) do
    reader = Accounts.register_user!("s3-export-reader@example.test", "Result Reader")
    Organizations.add_member!(context.org.id, reader.id)
    role = Authorization.create_role!(context.org.id, "result-reader", "Result Reader")
    Authorization.assign_role!(context.org.id, reader.id, role.id)

    capability =
      Authorization.create_capability!("tasks.results.read", "Read results",
        upsert?: true,
        upsert_identity: :key,
        upsert_fields: []
      )

    Authorization.grant_capability!(role.id, capability.id)
    reader
  end

  defp scope(ctx),
    do: "organizationId: \"#{ctx.context.org.id}\", projectId: \"#{ctx.project.id}\""

  defp bearer(conn, actor),
    do:
      put_req_header(
        conn,
        "authorization",
        "Bearer #{Accounts.issue_bearer_session!(actor.id).token}"
      )

  defp request(conn, query) do
    response = post(conn, "/graphql", %{query: query})
    assert get_resp_header(response, "cache-control") == ["no-store"]
    json_response(response, 200)
  end

  defp download!(ctx, descriptor) do
    Req.get!(ctx.request,
      url: descriptor["uri"],
      headers: Jason.decode!(descriptor["headers"])
    )
  end
end
