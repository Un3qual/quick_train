defmodule QuickTrain.Forms.FormIntegrityTest do
  use QuickTrain.DataCase, async: false
  @moduletag :committed_db
  import QuickTrain.FormsFixture

  alias QuickTrain.Forms
  alias QuickTrain.Forms.{FormVersion, Graph}
  alias QuickTrain.Forms.Inputs.{InputFieldRequirement, InputSlotDefinition}
  alias QuickTrain.Forms.Presentation.PresentationElement
  alias QuickTrain.Forms.Questions.Constraints.{IntegerConstraints, TextConstraints}
  alias QuickTrain.Forms.Questions.QuestionDefinition

  setup do
    ctx = context!()
    Map.merge(ctx, rating!(ctx))
  end

  test "published graphs reject authoring actions even with stale draft records", ctx do
    published = run!(FormVersion, :publish, ctx, %{version_id: ctx.version.id})
    graph = Graph.load!(published.id)
    stored_version = Ash.get!(FormVersion, published.id, authorize?: false)

    for record <- [ctx.slot, ctx.field, ctx.question, ctx.bounds, ctx.element] do
      assert {:error, error} = edit(record.__struct__, ctx, record, %{})
      assert Exception.message(error) =~ "version_not_draft"

      assert {:error, error} =
               run(record.__struct__, :remove_from_draft, ctx, %{
                 version_id: published.id,
                 id: record.id
               })

      assert Exception.message(error) =~ "version_not_draft"
    end

    assert {:error, error} =
             Forms.update_form_draft(ctx.version, ctx.org.id, %{title: "Changed"},
               actor: ctx.actor
             )

    assert Exception.message(error) =~ "version_not_draft"

    assert {:error, error} =
             run(InputSlotDefinition, :add_to_draft, ctx, %{
               version_id: published.id,
               key: "late",
               minimum: 1,
               maximum: 1
             })

    assert Exception.message(error) =~ "version_not_draft"

    assert {:error, error} =
             run(PresentationElement, :reorder, ctx, %{
               version_id: published.id,
               ids: [ctx.element.id]
             })

    assert Exception.message(error) =~ "version_not_draft"
    assert Graph.load!(published.id) == graph
    assert Ash.get!(FormVersion, published.id, authorize?: false) == stored_version
  end

  test "authoring cannot change identity, ownership, keys, or lifecycle fields", ctx do
    other = run!(FormVersion, :create_draft, ctx, %{form_id: ctx.form.id})
    stored_version = Ash.get!(FormVersion, ctx.version.id, authorize?: false)

    for {record, attributes} <- [
          {ctx.slot, %{id: Ash.UUID.generate()}},
          {ctx.slot, %{key: "changed"}},
          {ctx.slot, %{version_id: other.id}},
          {ctx.field, %{input_slot_id: Ash.UUID.generate()}},
          {ctx.bounds, %{question_id: Ash.UUID.generate()}},
          {ctx.element, %{kind: :heading}}
        ] do
      stored_record = Ash.get!(record.__struct__, record.id, authorize?: false)

      assert {:error, _} =
               Ash.update(
                 record,
                 Map.merge(
                   %{organization_id: ctx.org.id, version_id: ctx.version.id},
                   attributes
                 ),
                 action: :update_in_draft,
                 actor: ctx.actor
               )

      assert Ash.get!(record.__struct__, record.id, authorize?: false) == stored_record
    end

    for attributes <- [
          %{version: 99},
          %{form_id: Ash.UUID.generate()},
          %{state: :published},
          %{published_at: DateTime.utc_now()}
        ] do
      assert {:error, _} =
               Forms.update_form_draft(ctx.version, ctx.org.id, attributes, actor: ctx.actor)
    end

    assert {:error, _} =
             run(FormVersion, :create_draft, ctx, %{
               form_id: ctx.form.id,
               state: :published,
               published_at: DateTime.utc_now()
             })

    assert Ash.get!(FormVersion, ctx.version.id, authorize?: false) == stored_version
    assert Ash.count!(FormVersion, authorize?: false) == 2

    assert {:error, _} =
             Forms.add_form_input_slot_definition(
               ctx.org.id,
               %{
                 id: Ash.UUID.generate(),
                 version_id: ctx.version.id,
                 key: "caller_supplied_id",
                 minimum: 1,
                 maximum: 1
               },
               actor: ctx.actor
             )

    assert Ash.count!(InputSlotDefinition, authorize?: false) == 1
  end

  test "invalid presentation content and wrong-family children roll back in Ash", ctx do
    assert {:error, _} =
             run(PresentationElement, :add_to_draft, ctx, %{
               version_id: ctx.version.id,
               kind: :heading,
               position: 99,
               text: " "
             })

    assert {:error, error} =
             run(TextConstraints, :add_to_draft, ctx, %{
               version_id: ctx.version.id,
               question_id: ctx.question.id
             })

    assert Exception.message(error) =~ "incompatible constraints"
    assert Ash.count!(TextConstraints, authorize?: false) == 0
    assert Ash.count!(PresentationElement, authorize?: false) == 1
  end

  test "same-version references and internal GraphQL integer bounds are enforced", ctx do
    other = run!(FormVersion, :create_draft, ctx, %{form_id: ctx.form.id})

    assert {:error, %Postgrex.Error{postgres: %{code: :foreign_key_violation}}} =
             Repo.query(
               "INSERT INTO form_input_field_requirements (version_id, input_slot_id, key, value_family, cardinality, required) VALUES ($1, $2, 'cross', 'text', 'single', true)",
               Enum.map([other.id, ctx.slot.id], &Ecto.UUID.dump!/1)
             )

    assert {:error, _} =
             Ash.create(
               IntegerConstraints,
               %{
                 version_id: ctx.version.id,
                 question_id: ctx.question.id,
                 maximum: 2_147_483_648
               },
               action: :create_internal,
               authorize?: false
             )

    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
             Repo.query(
               "UPDATE form_integer_constraints SET maximum = 2147483648 WHERE id = $1",
               [Ecto.UUID.dump!(ctx.bounds.id)]
             )
  end

  test "a mid-copy database failure rolls back children and version allocation", ctx do
    run!(FormVersion, :publish, ctx, %{version_id: ctx.version.id})

    Repo.query!(
      "ALTER TABLE form_integer_constraints ADD CONSTRAINT injected_copy_failure CHECK (id = '#{ctx.bounds.id}')"
    )

    try do
      assert {:error, error} =
               run(FormVersion, :copy_published, ctx, %{
                 form_id: ctx.form.id,
                 source_version_id: ctx.version.id
               })

      assert Exception.message(error) =~ "injected_copy_failure"
      assert Ash.count!(FormVersion, authorize?: false) == 1
      assert Ash.count!(QuestionDefinition, authorize?: false) == 1
      assert run!(FormVersion, :create_draft, ctx, %{form_id: ctx.form.id}).version == 2
    after
      Repo.query!("ALTER TABLE form_integer_constraints DROP CONSTRAINT injected_copy_failure")
    end
  end

  test "publication reports each contract issue once", ctx do
    Repo.query!(
      "UPDATE form_question_definitions SET renderer = 'text_input' WHERE id = $1",
      [Ecto.UUID.dump!(ctx.question.id)]
    )

    assert {:error, error} = run(FormVersion, :publish, ctx, %{version_id: ctx.version.id})
    assert [%QuickTrain.Forms.Error{issues: [issue], truncated: false}] = error.errors
    assert issue == "#{ctx.question.id}: incompatible renderer"
  end

  test "later-page invalid definitions are validated and issue output is capped", ctx do
    for n <- 1..101 do
      question =
        Ash.create!(
          QuestionDefinition,
          %{
            version_id: ctx.version.id,
            key: "q#{n}",
            prompt: "Private prompt #{n}",
            family: :boolean,
            renderer: :toggle
          },
          action: :create_internal,
          authorize?: false
        )

      if n < 101,
        do:
          add!(PresentationElement, ctx, ctx.version, %{
            kind: :question,
            position: n + 10,
            question_id: question.id
          })
    end

    assert {:error, error} = run(FormVersion, :publish, ctx, %{version_id: ctx.version.id})
    assert Exception.message(error) =~ "exactly one placement"
    refute Exception.message(error) =~ "Private prompt"

    for element <- Graph.load!(ctx.version.id)[PresentationElement] do
      run!(PresentationElement, :remove_from_draft, ctx, %{
        version_id: ctx.version.id,
        id: element.id
      })
    end

    assert {:error, error} = run(FormVersion, :publish, ctx, %{version_id: ctx.version.id})
    assert Exception.message(error) =~ "truncated"
    [%QuickTrain.Forms.Error{issues: issues}] = error.errors
    assert Enum.count(issues) == 100
  end

  test "destination graph count limits fail atomically during authoring and copy", ctx do
    for n <- 2..32,
        do:
          add!(InputSlotDefinition, ctx, ctx.version, %{key: "slot#{n}", minimum: 1, maximum: 1})

    assert {:error, _} =
             run(InputSlotDefinition, :add_to_draft, ctx, %{
               version_id: ctx.version.id,
               key: "overflow",
               minimum: 1,
               maximum: 1
             })

    assert Ash.count!(InputSlotDefinition, authorize?: false) == 32
    # Simulates an older source authored with a larger per-slot limit; inspection stays available.
    for n <- 2..65,
        do:
          Ash.create!(
            InputFieldRequirement,
            %{
              version_id: ctx.version.id,
              input_slot_id: ctx.slot.id,
              key: "f#{n}",
              value_family: :text,
              required: false
            },
            action: :create_internal,
            authorize?: false
          )

    Ash.update!(ctx.version, %{}, action: :publish_internal, authorize?: false)

    assert {:error, _} =
             run(FormVersion, :copy_published, ctx, %{
               form_id: ctx.form.id,
               source_version_id: ctx.version.id
             })

    assert Ash.count!(FormVersion, authorize?: false) == 1
    assert run!(FormVersion, :create_draft, ctx, %{form_id: ctx.form.id}).version == 2
  end
end
