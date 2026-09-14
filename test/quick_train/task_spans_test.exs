defmodule QuickTrain.Tasks.TextSpansTest do
  use QuickTrain.DataCase, async: false

  alias QuickTrain.{
    Accounts,
    Authorization,
    Datasets,
    Forms,
    FormsFixture,
    Organizations,
    ProjectsFixture
  }

  alias QuickTrain.Datasets.DatasetValue
  alias QuickTrain.Forms.Inputs.{InputFieldRequirement, InputSlotDefinition}
  alias QuickTrain.Forms.Labels.{Label, LabelSet}
  alias QuickTrain.Forms.Presentation.PresentationElement
  alias QuickTrain.Forms.Questions.Constraints.AnnotationConstraints
  alias QuickTrain.Forms.Questions.QuestionDefinition
  alias QuickTrain.Tasks.{Attempt, Response, TaskInput, TaskQuestionProgress, TextSpan}
  alias QuickTrainWeb.GraphQL.Schema

  require Ash.Query

  @text "A😀éZ" <> String.duplicate("x", 155)

  setup do
    context = ProjectsFixture.context!()
    source = source!(context)

    project =
      ProjectsFixture.active!(context, source,
        audience: :external_users,
        external_access: :open
      )

    worker = Accounts.register_user!("span-worker@example.test", "Worker")
    reader = reader!(context)
    ctx = %{context: context, source: source, project: project, worker: worker, reader: reader}

    assert {:ok, %{status: :issued, attempt: attempt}} =
             action(ctx, Attempt, :fetch, %{request_key: Ash.UUID.generate()})

    input = Ash.read_one!(TaskInput, authorize?: false)
    ctx = Map.merge(ctx, %{attempt: attempt, input: input})
    assert {:ok, bound} = bound(ctx)
    Map.put(ctx, :value, bound.value)
  end

  test "overlapping code-point spans retain pinned source and label identities after submission",
       ctx do
    spans = [span(ctx, 1, 5), span(ctx, 2, 4)]
    assert {:ok, %{revision: 1}} = save(ctx, 0, spans)
    original = Ash.read!(TextSpan, authorize?: false, page: false)
    assert MapSet.new(original, &{&1.start, &1.end}) == MapSet.new([{1, 5}, {2, 4}])

    replacement =
      Datasets.put_item_revision!(
        ctx.context.org.id,
        ctx.source.dataset.id,
        ctx.source.schema.id,
        hd(ctx.source.revisions).item_id,
        "document",
        [%{field: "body", text: "A newer document"}],
        actor: ctx.context.actor
      ).revision

    newer_value =
      DatasetValue
      |> Ash.Query.filter(record_id == ^replacement.root_record_id)
      |> Ash.read_one!(authorize?: false)

    assert {:error, _} = save(ctx, 1, [%{span(ctx, 1, 5) | source_value_id: newer_value.id}])
    assert {:ok, bound} = bound(ctx)
    assert bound.value.id == ctx.value.id
    assert bound.revision_id == hd(ctx.source.revisions).id

    assert {:error, _} =
             FormsFixture.edit(Label, ctx.context, ctx.source.form.label, %{text: "Changed"})

    assert {:ok, submitted} = action(ctx, Response, :submit, %{attempt_id: ctx.attempt.id})
    assert submitted.state == :submitted
    assert {:ok, retry} = action(ctx, Response, :submit, %{attempt_id: ctx.attempt.id})
    assert retry.id == submitted.id
    assert {:error, _} = save(ctx, 1, [span(ctx, 0, 1)])

    [existing | _] = original

    assert_raise Ash.Error.Invalid, ~r/response_submitted/, fn ->
      Ash.destroy!(existing, action: :destroy_internal, authorize?: false)
    end

    attrs =
      existing
      |> Map.take([
        :organization_id,
        :project_id,
        :form_version_id,
        :task_id,
        :question_id,
        :question_response_id,
        :task_input_id,
        :source_value_id,
        :label_id
      ])
      |> Map.merge(%{start: 0, end: 1})

    assert_raise Ash.Error.Invalid, ~r/response_submitted/, fn ->
      Ash.create!(TextSpan, attrs, action: :create_internal, authorize?: false)
    end

    assert MapSet.new(Ash.read!(TextSpan, authorize?: false, page: false), & &1.id) ==
             MapSet.new(original, & &1.id)

    page = graphql_page(ctx)

    assert Enum.map(page["edges"], & &1["node"]["sourceValue"]["textValue"]["value"]) == [
             @text,
             @text
           ]

    assert Enum.all?(page["edges"], &(&1["node"]["label"]["id"] == ctx.source.form.label.id))
    assert Enum.all?(page["edges"], &(&1["node"]["taskInput"]["revisionId"] == bound.revision_id))
    assert Ash.read_one!(TaskQuestionProgress, authorize?: false).accepted == 1
  end

  test "more than one hundred submitted spans remain fully traversable through Ash and GraphQL",
       ctx do
    spans = Enum.map(0..150, &span(ctx, &1, &1 + 1))
    assert {:ok, %{revision: 1}} = save(ctx, 0, spans)

    assert {:ok, %{state: :submitted}} =
             action(ctx, Response, :submit, %{attempt_id: ctx.attempt.id})

    ash_page = read_page!(ctx, :list_accepted)
    assert Enum.count(ash_page.results) == 50
    assert ash_page.more?
    ash_spans = all_pages(ash_page)
    assert Enum.count(ash_spans) == 151
    assert MapSet.size(MapSet.new(ash_spans, & &1.id)) == 151
    first = graphql_page(ctx)
    assert Enum.count(first["edges"]) == 100
    assert first["pageInfo"]["hasNextPage"]
    second = graphql_page(ctx, first["pageInfo"]["endCursor"])
    assert Enum.count(second["edges"]) == 51
    refute second["pageInfo"]["hasNextPage"]
    edges = first["edges"] ++ second["edges"]
    assert Enum.map(edges, & &1["node"]["id"]) == Enum.map(ash_spans, & &1.id)

    assert MapSet.new(edges, &{&1["node"]["start"], &1["node"]["end"]}) ==
             MapSet.new(0..150, &{&1, &1 + 1})

    assert {:error, _} =
             TextSpan
             |> Ash.Query.for_read(:list_accepted, scope(ctx), actor: ctx.worker)
             |> Ash.read()
  end

  test "released span drafts remain stored but lose worker access and result visibility", ctx do
    assert {:ok, _} = save(ctx, 0, [span(ctx, 1, 5)])

    assert {:ok, %{state: :released}} =
             action(ctx, Attempt, :release, %{attempt_id: ctx.attempt.id})

    assert {:error, _} = bound(ctx)
    assert {:error, _} = save(ctx, 1, [span(ctx, 0, 1)])
    assert Ash.count!(TextSpan, authorize?: false) == 1
    assert read_page!(ctx, :list_accepted).results == []
    assert read_page!(ctx, :list_audit).results == []
    assert graphql_page(ctx)["edges"] == []
  end

  defp read_page!(ctx, action) do
    TextSpan
    |> Ash.Query.for_read(action, scope(ctx), actor: ctx.reader)
    |> Ash.read!()
  end

  defp all_pages(%{more?: false, results: results}), do: results
  defp all_pages(page), do: page.results ++ all_pages(Ash.page!(page, :next))

  defp graphql_page(ctx, after_cursor \\ nil) do
    query = """
    query($after: String) {
      acceptedTextSpans(organizationId: "#{ctx.context.org.id}", projectId: "#{ctx.project.id}", first: 100, after: $after) {
        edges { cursor node { id start end taskInput { id revisionId } label { id text } sourceValue { id textValue { value } } } }
        pageInfo { hasNextPage endCursor }
      }
    }
    """

    assert {:ok, result} =
             Absinthe.run(query, Schema,
               variables: %{"after" => after_cursor},
               context: %{actor: ctx.reader}
             )

    refute Map.has_key?(result, :errors), inspect(result)
    result.data["acceptedTextSpans"]
  end

  defp span(ctx, start, finish),
    do: %{
      task_input_id: ctx.input.id,
      source_value_id: ctx.value.id,
      label_id: ctx.source.form.label.id,
      start: start,
      end: finish
    }

  defp save(ctx, revision, spans),
    do:
      action(ctx, Response, :save_question, %{
        attempt_id: ctx.attempt.id,
        question_id: ctx.source.form.question.id,
        expected_revision: revision,
        answer: %{outcome: :answered, family: :text_spans, spans: spans}
      })

  defp bound(ctx),
    do:
      action(ctx, TaskInput, :bound_value, %{
        attempt_id: ctx.attempt.id,
        task_input_id: ctx.input.id,
        requirement_id: ctx.source.form.field.id
      })

  defp action(ctx, resource, name, args) do
    resource
    |> Ash.ActionInput.for_action(name, Map.merge(scope(ctx), args), actor: ctx.worker)
    |> Ash.run_action()
  end

  defp scope(ctx), do: %{organization_id: ctx.context.org.id, project_id: ctx.project.id}

  defp reader!(context) do
    reader = Accounts.register_user!("span-reader@example.test", "Result Reader")
    Organizations.add_member!(context.org.id, reader.id)
    role = Authorization.create_role!(context.org.id, "results", "Results")
    Authorization.assign_role!(context.org.id, reader.id, role.id)

    capability =
      Authorization.create_capability!("tasks.results.read", "Results",
        upsert?: true,
        upsert_identity: :key,
        upsert_fields: []
      )

    Authorization.grant_capability!(role.id, capability.id)
    reader
  end

  defp source!(context) do
    form = span_form!(context)

    dataset =
      Datasets.create_dataset!(context.org.id, "documents", "Documents", actor: context.actor)

    schema = Datasets.create_schema_version!(context.org.id, dataset.id, actor: context.actor)

    root =
      Datasets.add_record_type!(context.org.id, schema.id, "document", "Document",
        actor: context.actor
      )

    field =
      Datasets.add_field_definition!(
        context.org.id,
        root.id,
        "body",
        "Body",
        "text",
        "single",
        true,
        actor: context.actor
      )

    schema =
      Datasets.publish_schema_version!(context.org.id, schema.id, root.id, actor: context.actor)

    revision =
      Datasets.put_item_revision!(
        context.org.id,
        dataset.id,
        schema.id,
        nil,
        "document",
        [%{field: "body", text: @text}],
        actor: context.actor
      ).revision

    %{
      form: form,
      dataset: dataset,
      schema: schema,
      root: root,
      field: field,
      revisions: [revision]
    }
  end

  defp span_form!(context) do
    form = FormsFixture.draft!(context)

    slot =
      FormsFixture.add!(InputSlotDefinition, context, form.version, %{
        key: "item",
        minimum: 1,
        maximum: 1
      })

    field =
      FormsFixture.add!(InputFieldRequirement, context, form.version, %{
        input_slot_id: slot.id,
        key: "body",
        value_family: :text,
        required: true
      })

    labels = FormsFixture.add!(LabelSet, context, form.version, %{key: "tags", name: "Tags"})

    label =
      FormsFixture.add!(Label, context, form.version, %{
        label_set_id: labels.id,
        key: "tag",
        text: "Tag",
        position: 0
      })

    question =
      FormsFixture.add!(QuestionDefinition, context, form.version, %{
        key: "spans",
        prompt: "Mark spans",
        family: :text_spans,
        renderer: :text_spans
      })

    FormsFixture.add!(AnnotationConstraints, context, form.version, %{
      question_id: question.id,
      source_requirement_id: field.id,
      label_set_id: labels.id,
      minimum: 1,
      maximum: 500
    })

    FormsFixture.add!(PresentationElement, context, form.version, %{
      kind: :question,
      position: 0,
      question_id: question.id
    })

    version =
      Forms.publish_form_version!(context.org.id, %{version_id: form.version.id},
        actor: context.actor
      )

    Map.merge(form, %{
      version: version,
      slot: slot,
      field: field,
      question: question,
      label: label
    })
  end
end
