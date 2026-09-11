defmodule QuickTrainWeb.FormGraphqlTest do
  use QuickTrain.ConnCase, async: false
  import QuickTrain.FormsFixture
  alias QuickTrain.Accounts
  alias QuickTrain.Forms.Presentation.PresentationElement
  alias QuickTrain.Forms.Questions.Constraints.SelectionConstraints
  alias QuickTrain.Forms.Questions.{QuestionDefinition, QuestionOption}

  test "native presentation mutations return and edit element content", %{
    conn: conn
  } do
    ctx = context!(~w(forms.manage))
    conn = bearer(conn, ctx.actor)

    form =
      graphql!(conn, """
      mutation { createForm(organizationId: "#{ctx.org.id}", key: "native") {
        result { id } errors { message }
      } }
      """)["createForm"]

    assert form["errors"] == []

    version =
      graphql!(conn, """
      mutation { createFormDraft(organizationId: "#{ctx.org.id}", formId: "#{form["result"]["id"]}", title: "Native") {
        result { id } errors { message }
      } }
      """)["createFormDraft"]

    assert version["errors"] == []
    version_id = version["result"]["id"]

    element =
      graphql!(conn, """
      mutation { addFormPresentationElement(organizationId: "#{ctx.org.id}", versionId: "#{version_id}", kind: HEADING, position: 0, text: "Heading") {
        result { id text } errors { message }
      } }
      """)["addFormPresentationElement"]

    assert element["errors"] == []
    assert element["result"]["text"] == "Heading"

    updated =
      graphql!(conn, """
      mutation { updateFormPresentationElement(organizationId: "#{ctx.org.id}", versionId: "#{version_id}", id: "#{element["result"]["id"]}", text: "Updated heading") {
        result { id text } errors { message }
      } }
      """)["updateFormPresentationElement"]

    assert updated["errors"] == []
    assert updated["result"]["text"] == "Updated heading"

    result =
      graphql!(conn, """
      mutation { removeFormPresentationElement(organizationId: "#{ctx.org.id}", versionId: "#{version_id}", id: "#{element["result"]["id"]}") {
        errors { message }
      } }
      """)["removeFormPresentationElement"]

    assert result["errors"] == []
    assert Ash.count!(PresentationElement, authorize?: false) == 0
  end

  test "a manage-only actor receives the authorized graph but has no general read API", %{
    conn: conn
  } do
    ctx = context!(~w(forms.manage))
    graph = rating!(ctx)
    conn = bearer(conn, ctx.actor)

    data =
      graphql!(conn, """
      mutation { publishFormVersion(organizationId: "#{ctx.org.id}", versionId: "#{graph.version.id}") {
        id version state publishedAt title
        inputSlots(first: 2) { edges { node { id key minimum maximum requirements(first: 2) { edges { node { valueFamily cardinality required } } } } } }
        questions(first: 2) { edges { node { id key prompt family renderer integerConstraints { minimum maximum } } } }
        elements(first: 2) { edges { node { id kind position question { id } } } }
      } }
      """)

    published = data["publishFormVersion"]
    assert published["state"] == "PUBLISHED"

    assert [%{"node" => %{"integerConstraints" => %{"minimum" => 1, "maximum" => 5}}}] =
             published["questions"]["edges"]

    response =
      conn
      |> post("/graphql", %{
        query:
          "{ formVersion(organizationId: \"#{ctx.org.id}\", id: \"#{graph.version.id}\") { id } }"
      })
      |> json_response(200)

    assert response["errors"] != []
    refute get_in(response, ["data", "formVersion"])
  end

  test "authenticated typed authoring and cursor pagination preserve all options", %{conn: conn} do
    ctx = context!()
    graph = rating!(ctx)
    conn = bearer(conn, ctx.actor)

    question =
      add!(QuestionDefinition, ctx, graph.version, %{
        key: "choice",
        prompt: "Choose",
        family: :static_single_choice,
        renderer: :radio
      })

    add!(SelectionConstraints, ctx, graph.version, %{
      question_id: question.id,
      minimum: 1,
      maximum: 1
    })

    for n <- 0..100,
        do:
          add!(QuestionOption, ctx, graph.version, %{
            question_id: question.id,
            key: "o#{n}",
            label: "Option #{n}",
            position: n * 2
          })

    first = options_page(conn, ctx, graph.version.id, question.id, nil)
    assert Enum.count(first["edges"]) == 50
    assert first["pageInfo"]["hasNextPage"]

    second =
      options_page(conn, ctx, graph.version.id, question.id, first["pageInfo"]["endCursor"])

    last = options_page(conn, ctx, graph.version.id, question.id, second["pageInfo"]["endCursor"])
    assert Enum.count(second["edges"]) == 50
    assert Enum.count(last["edges"]) == 1
    refute last["pageInfo"]["hasNextPage"]

    assert Enum.map(first["edges"] ++ second["edges"] ++ last["edges"], & &1["node"]["position"]) ==
             Enum.map(0..100, &(&1 * 2))

    updated =
      graphql!(conn, """
      mutation { updateFormQuestionDefinition(organizationId: "#{ctx.org.id}", versionId: "#{graph.version.id}", id: "#{question.id}", prompt: "Choose one") { result { id prompt } errors { message } } }
      """)

    assert updated["updateFormQuestionDefinition"]["result"]["prompt"] == "Choose one"
  end

  test "manage-only authors can inspect direct question sources and bound references", %{
    conn: conn
  } do
    ctx = context!(~w(forms.manage))
    graph = rating!(ctx)
    conn = bearer(conn, ctx.actor)

    image =
      add!(QuickTrain.Forms.Inputs.InputFieldRequirement, ctx, graph.version, %{
        key: "image",
        input_slot_id: graph.slot.id,
        value_family: :asset,
        intended_use: :image,
        required: true
      })

    result =
      graphql!(conn, """
      mutation { addFormQuestionDefinition(organizationId: "#{ctx.org.id}", versionId: "#{graph.version.id}", key: "image-choice", prompt: "Choose", family: TASK_INPUT_SINGLE_CHOICE, renderer: IMAGE_CHOICE, inputSlotId: "#{graph.slot.id}", sourceRequirementId: "#{image.id}") {
        result { id inputSlot { id } sourceRequirement { id valueFamily } } errors { message }
      } }
      """)["addFormQuestionDefinition"]

    assert result["errors"] == []
    assert result["result"]["inputSlot"]["id"] == graph.slot.id
    assert result["result"]["sourceRequirement"] == %{"id" => image.id, "valueFamily" => "ASSET"}

    element =
      graphql!(conn, """
      mutation { addFormPresentationElement(organizationId: "#{ctx.org.id}", versionId: "#{graph.version.id}", kind: BOUND_VALUE, position: 20, requirementId: "#{graph.field.id}") {
        result { id requirement { id key } } errors { message }
      } }
      """)["addFormPresentationElement"]

    assert element["errors"] == []
    assert element["result"]["requirement"]["id"] == graph.field.id
  end

  test "query complexity and request byte limits apply to Forms", %{conn: conn} do
    ctx = context!()
    conn = bearer(conn, ctx.actor)

    response =
      conn
      |> post("/graphql", %{
        query: """
          { forms(organizationId: "#{ctx.org.id}", first: 100) { edges { node { versions(first: 100) { edges { node { questions(first: 100) { edges { node { options(first: 100) { edges { node { id } } } } } } } } } } } } }
        """
      })
      |> json_response(200)

    assert Enum.any?(response["errors"], &String.contains?(&1["message"], "too complex"))
    body = Jason.encode!(%{query: String.duplicate(" ", 512 * 1024)})

    assert_raise Plug.Parsers.RequestTooLargeError, fn ->
      conn |> put_req_header("content-type", "application/json") |> post("/graphql", body)
    end
  end

  test "authenticated failures preserve explicit organization scope", %{conn: conn} do
    ctx = context!()
    graph = rating!(ctx)
    outsider = Accounts.register_user!("outside-forms@example.test", "Outside")
    member = Accounts.register_user!("no-forms-capability@example.test", "Member")
    QuickTrain.Organizations.add_member!(ctx.org.id, member.id)

    query =
      "mutation { publishFormVersion(organizationId: \"#{ctx.org.id}\", versionId: \"#{graph.version.id}\") { id } }"

    for actor <- [outsider, member] do
      response = conn |> bearer(actor) |> post("/graphql", %{query: query}) |> json_response(200)
      assert response["errors"] != []
      refute get_in(response, ["data", "publishFormVersion"])
    end

    manager_conn = bearer(conn, ctx.actor)
    QuickTrain.Organizations.deactivate_membership!(ctx.membership)
    response = manager_conn |> post("/graphql", %{query: query}) |> json_response(200)
    assert response["errors"] != []
    QuickTrain.Organizations.add_member!(ctx.org.id, ctx.actor.id)
    Ash.update!(ctx.org, %{status: "inactive"}, action: :update, authorize?: false)
    response = manager_conn |> post("/graphql", %{query: query}) |> json_response(200)
    assert response["errors"] != []
    Ash.update!(ctx.actor, %{status: "disabled"}, action: :set_status, authorize?: false)
    assert manager_conn |> post("/graphql", %{query: query}) |> response(401)
  end

  test "annotation inspection returns fixed conventions without data or storage reads", %{
    conn: conn
  } do
    ctx = context!()
    graph = rating!(ctx)

    question =
      add!(QuickTrain.Forms.Questions.QuestionDefinition, ctx, graph.version, %{
        key: "span",
        prompt: "Mark text",
        family: :text_spans,
        renderer: :text_spans
      })

    set = add!(QuickTrain.Forms.Labels.LabelSet, ctx, graph.version, %{key: "labels"})

    add!(QuickTrain.Forms.Questions.Constraints.AnnotationConstraints, ctx, graph.version, %{
      question_id: question.id,
      source_requirement_id: graph.field.id,
      label_set_id: set.id,
      minimum: 0,
      maximum: 10
    })

    handler = "forms-inspection-#{System.unique_integer([:positive])}"
    parent = self()

    :ok =
      :telemetry.attach(
        handler,
        [:quick_train, :repo, :query],
        fn _, _, metadata, _ ->
          if Regex.match?(~r/\b(?:FROM|JOIN)\s+"(?:assets|dataset_)/, metadata.query),
            do: send(parent, :content_read)
        end,
        nil
      )

    try do
      data =
        graphql!(bearer(conn, ctx.actor), """
        { formVersion(organizationId: "#{ctx.org.id}", id: "#{graph.version.id}") {
          questions(first: 2) { edges { node { id annotationConstraints { sourceConvention minimum maximum sourceRequirement { valueFamily } } } } }
        } }
        """)

      node =
        Enum.find(data["formVersion"]["questions"]["edges"], &(&1["node"]["id"] == question.id))

      assert node["node"]["annotationConstraints"]["sourceConvention"] ==
               "unicode_codepoints_zero_based_end_exclusive"

      refute_receive :content_read
    after
      :telemetry.detach(handler)
    end
  end

  defp options_page(conn, ctx, version_id, question_id, cursor) do
    after_arg = if cursor, do: ", after: \"#{cursor}\"", else: ""

    data =
      graphql!(conn, """
        { formVersion(organizationId: "#{ctx.org.id}", id: "#{version_id}") {
          questions(first: 2) { edges { node { id options(#{if cursor, do: "first: 50" <> after_arg, else: "first: 50"}) {
            edges { node { id position } } pageInfo { hasNextPage endCursor }
          } } } }
        } }
      """)

    node =
      Enum.find(data["formVersion"]["questions"]["edges"], &(&1["node"]["id"] == question_id))

    node["node"]["options"]
  end

  defp bearer(conn, actor) do
    session = Accounts.issue_bearer_session!(actor.id)
    put_req_header(conn, "authorization", "Bearer #{session.token}")
  end
end
