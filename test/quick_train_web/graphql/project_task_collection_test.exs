defmodule QuickTrainWeb.ProjectTaskCollectionTest do
  use QuickTrain.ConnCase, async: false
  alias QuickTrain.{Accounts, Authorization, Organizations, ProjectsFixture, Tasks}
  alias QuickTrain.Assets.Storage.InMemory
  alias QuickTrain.Tasks.Attempts.Attempt
  require Ash.Query

  setup do
    context = ProjectsFixture.context!()
    source = ProjectsFixture.source!(context)

    project =
      ProjectsFixture.active!(context, source, audience: :external_users, external_access: :open)

    worker = Accounts.register_user!("graphql-worker@example.test", "Collector")
    reader = member!(context, "reader", ~w(tasks.results.read))
    %{context: context, source: source, project: project, worker: worker, reader: reader}
  end

  test "an external owner completes a typed collection and a result-only member reads its contract",
       ctx do
    conn = bearer(ctx.conn, ctx.worker)
    scope = scope(ctx)

    issued =
      graphql!(conn, """
      mutation { fetchWork(#{scope}, requestKey: "#{Ash.UUID.generate()}") {
        status attempt { id state deadline }
      } }
      """)["fetchWork"]

    assert issued["status"] == "issued"
    attempt = issued["attempt"]["id"]

    bundle =
      graphql!(conn, """
      { workBundle(#{scope}, attemptId: "#{attempt}") {
        id formVersion { id questions(first: 5) { edges { node { id renderer integerConstraints { minimum maximum } } } } }
        skipAllowed reasonRequired
        inputPresentations(first: 5) { edges { node { taskInputId position } } }
        revision
      } }
      """)["workBundle"]

    assert bundle["formVersion"]["id"] == ctx.source.form.version.id

    assert bundle["skipAllowed"]
    assert bundle["reasonRequired"]
    question = hd(bundle["formVersion"]["questions"]["edges"])["node"]["id"]
    assert question == ctx.source.form.question.id
    input = hd(bundle["inputPresentations"]["edges"])["node"]["taskInputId"]

    value =
      graphql!(conn, """
      { taskBoundValue(#{scope}, attemptId: "#{attempt}", taskInputId: "#{input}", requirementId: "#{ctx.source.form.field.id}") {
        missing revisionId value { id textValue { value } }
      } }
      """)["taskBoundValue"]

    refute value["missing"]
    assert value["value"]["textValue"]["value"] =~ "Body"

    saved =
      graphql!(conn, """
      mutation { saveTaskQuestion(#{scope}, attemptId: "#{attempt}", questionId: "#{question}", expectedRevision: 0,
        answer: {outcome: "answered", family: INTEGER, integerValue: 4}) { id revision }
      }
      """)["saveTaskQuestion"]

    assert saved["revision"] == 1

    assert graphql!(
             conn,
             "mutation { submitTaskResponse(#{scope}, attemptId: \"#{attempt}\") { id state } }"
           )["submitTaskResponse"]["state"] == "submitted"

    receipt =
      graphql!(conn, """
      { attemptReceipt(#{scope}, attemptId: "#{attempt}") { id state accepted pending rejected skipped } }
      """)["attemptReceipt"]

    assert receipt["state"] == "submitted"
    assert receipt["accepted"] == 1

    results =
      request(bearer(ctx.conn, ctx.reader), """
      { taskResults(#{scope}, acceptedOnly: true, first: 5) { edges { node {
        id integerValue question { renderer integerConstraints { minimum maximum } }
        attempt { workerId inputPresentations(first: 5) { edges { node { position } } } }
      } } } }
      """)

    refute results["errors"]

    assert [%{"node" => %{"integerValue" => 4}}] =
             results["data"]["taskResults"]["edges"]

    denied =
      request(
        bearer(ctx.conn, ctx.reader),
        "{ formVersion(organizationId: \"#{ctx.context.org.id}\", id: \"#{ctx.source.form.version.id}\") { id } }"
      )

    assert denied["errors"]
    assert request(conn, "{ workBundle(#{scope}, attemptId: \"#{attempt}\") { id } }")["errors"]
  end

  test "assignment and result inspection require separate grants",
       ctx do
    manager = member!(ctx.context, "assigner", ~w(tasks.assign))

    original =
      Tasks.fetch_work!(ctx.context.org.id, ctx.project.id, Ash.UUID.generate(),
        actor: ctx.worker
      ).attempt

    Tasks.release_attempt!(ctx.context.org.id, ctx.project.id, original.id, actor: ctx.worker)
    conn = bearer(ctx.conn, manager)

    assert request(
             conn,
             "{ tasks(#{scope(ctx)}, first: 5) { edges { node { id attempts(first: 5) { edges { node { id } } } } } } }"
           )[
             "errors"
           ]

    other = Accounts.register_user!("assigned-worker@example.test", "Assigned")

    assigned =
      graphql!(conn, """
      mutation { assignWork(#{scope(ctx)}, workerId: "#{other.id}", requestKey: "#{Ash.UUID.generate()}") {
        status attempt { id state }
      } }
      """)["assignWork"]["attempt"]

    assert assigned["state"] == "assigned"

    assert graphql!(
             conn,
             "mutation { cancelAttempt(#{scope(ctx)}, attemptId: \"#{assigned["id"]}\") { state } }"
           )["cancelAttempt"]["state"] == "cancelled"

    grant!(ctx.context, manager, "tasks.results.read")

    tasks =
      graphql!(
        conn,
        "{ tasks(#{scope(ctx)}, first: 5) { edges { node { id attempts(first: 5) { edges { node { id } } } } } } }"
      )["tasks"]["edges"]

    attempts = Enum.flat_map(tasks, & &1["node"]["attempts"]["edges"])
    assert Enum.any?(attempts, &(&1["node"]["id"] == original.id))
  end

  test "invalid keys and revoked eligibility fail closed through the HTTP boundary", ctx do
    conn = bearer(ctx.conn, ctx.worker)

    for key <- ["", "invalid"] do
      assert request(
               conn,
               "mutation { fetchWork(#{scope(ctx)}, requestKey: \"#{key}\") { status } }"
             )["errors"]
    end

    assert Ash.count!(Attempt, authorize?: false) == 0
    key = Ash.UUID.generate()
    Tasks.fetch_work!(ctx.context.org.id, ctx.project.id, key, actor: ctx.worker)

    QuickTrain.Projects.set_worker_access!(
      ctx.context.org.id,
      ctx.project.id,
      %{
        user_id: ctx.worker.id,
        disposition: :block
      },
      actor: ctx.context.actor
    )

    assert request(
             conn,
             "mutation { fetchWork(#{scope(ctx)}, requestKey: \"#{key}\") { status } }"
           )["errors"]
  end

  @tag :committed_db
  test "export request, status, and ready download use current authority and no-store", ctx do
    :ok = InMemory.reset()
    conn = bearer(ctx.conn, ctx.reader)
    key = Ash.UUID.generate()

    mutation =
      "mutation { requestResultExport(#{scope(ctx)}, requestKey: \"#{key}\", mode: \"audit\") { id state recordCount } }"

    response = request(conn, mutation)
    refute response["errors"]
    export = response["data"]["requestResultExport"]
    assert export["state"] == "queued"
    assert request(conn, mutation)["data"]["requestResultExport"]["id"] == export["id"]
    assert QuickTrain.Tasks.process_result_export(export["id"], authorize?: false) == :ok

    status =
      "{ resultExport(#{scope(ctx)}, exportId: \"#{export["id"]}\") { id state recordCount } }"

    ready = request(conn, status)
    refute ready["errors"]
    assert ready["data"]["resultExport"]["state"] == "ready"
    assert ready["data"]["resultExport"]["recordCount"] == "0"

    download =
      "{ resultExportDownload(#{scope(ctx)}, exportId: \"#{export["id"]}\") { asset { id mediaType } readAccess { uri expiresAt } } }"

    authorized = request(conn, download)
    refute authorized["errors"]

    assert authorized["data"]["resultExportDownload"]["asset"]["mediaType"] ==
             "application/x-ndjson"

    denied = bearer(ctx.conn, ctx.worker)
    assert request(denied, status)["errors"]
    assert request(denied, download)["errors"]
    assert request(denied, mutation)["errors"]
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

  defp member!(context, key, capabilities) do
    actor = Accounts.register_user!("#{key}@example.test", key)
    Organizations.add_member!(context.org.id, actor.id)
    role = Authorization.create_role!(context.org.id, key, key)
    Authorization.assign_role!(context.org.id, actor.id, role.id)
    Enum.each(capabilities, &grant!(context, actor, &1))
    actor
  end

  defp grant!(context, actor, key) do
    assignment =
      Authorization.RoleAssignment
      |> Ash.Query.filter(organization_id == ^context.org.id and user_id == ^actor.id)
      |> Ash.read_one!(authorize?: false)

    capability =
      Authorization.create_capability!(key, key,
        upsert?: true,
        upsert_identity: :key,
        upsert_fields: []
      )

    Authorization.grant_capability!(assignment.role_id, capability.id)
  end
end
