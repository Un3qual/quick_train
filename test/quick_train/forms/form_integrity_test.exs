defmodule QuickTrain.Forms.FormIntegrityTest do
  alias AshPostgres.DataLayer.Info, as: DataLayerInfo
  use QuickTrain.DataCase, async: false
  @moduletag :committed_db
  import QuickTrain.FormsFixture

  alias QuickTrain.Forms.{Authoring, FormVersion, Graph}
  alias QuickTrain.Forms.Inputs.{InputFieldRequirement, InputSlotDefinition}
  alias QuickTrain.Forms.Presentation.PresentationElement
  alias QuickTrain.Forms.Questions.Constraints.{IntegerConstraints, TextConstraints}
  alias QuickTrain.Forms.Questions.QuestionDefinition

  setup do
    ctx = context!()
    Map.merge(ctx, rating!(ctx))
  end

  test "published owners and descendants reject direct persistence changes", ctx do
    published = run!(FormVersion, :publish, ctx, %{version_id: ctx.version.id})
    graph = Graph.load!(published.id)

    for {resource, records} <- graph, record <- records do
      table = DataLayerInfo.table(resource)

      for sql <- [
            "UPDATE #{table} SET updated_at = now() WHERE id = $1",
            "DELETE FROM #{table} WHERE id = $1"
          ] do
        assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
                 Repo.query(sql, [Ecto.UUID.dump!(record.id)])
      end
    end

    for sql <- [
          "UPDATE form_versions SET title = 'Changed' WHERE id = $1",
          "DELETE FROM form_versions WHERE id = $1"
        ] do
      assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
               Repo.query(sql, [Ecto.UUID.dump!(published.id)])
    end

    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
             Repo.query(
               "INSERT INTO form_input_slot_definitions (version_id, key, minimum, maximum) VALUES ($1, 'late', 1, 1)",
               [Ecto.UUID.dump!(published.id)]
             )

    other = run!(FormVersion, :create_draft, ctx, %{form_id: ctx.form.id})

    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
             Repo.query(
               "UPDATE form_input_slot_definitions SET version_id = $1 WHERE id = $2",
               Enum.map([other.id, ctx.slot.id], &Ecto.UUID.dump!/1)
             )

    assert Graph.load!(published.id) == graph
  end

  test "ownership and authored keys are immutable even on drafts", ctx do
    other = run!(FormVersion, :create_draft, ctx, %{form_id: ctx.form.id})

    for {sql, params} <- [
          {"UPDATE form_input_slot_definitions SET key = 'changed' WHERE id = $1", [ctx.slot.id]},
          {"UPDATE form_input_slot_definitions SET version_id = $1 WHERE id = $2",
           [other.id, ctx.slot.id]},
          {"UPDATE form_versions SET version = 99 WHERE id = $1", [ctx.version.id]},
          {"UPDATE forms SET key = 'changed' WHERE id = $1", [ctx.form.id]}
        ] do
      assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
               Repo.query(sql, Enum.map(params, &Ecto.UUID.dump!/1))
    end
  end

  @tag capture_log: true
  test "presentation subtype and wrong-family constraints fail at transaction commit", ctx do
    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
             Repo.query(
               "INSERT INTO form_presentation_elements (version_id, kind, position) VALUES ($1, 'heading', 99)",
               [Ecto.UUID.dump!(ctx.version.id)]
             )

    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
             Repo.query(
               "INSERT INTO form_text_constraints (version_id, question_id) VALUES ($1, $2)",
               Enum.map([ctx.version.id, ctx.question.id], &Ecto.UUID.dump!/1)
             )

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

    Repo.query!("""
    CREATE FUNCTION pg_temp.reject_form_copy() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN RAISE EXCEPTION 'injected copy failure' USING ERRCODE = '23514'; END $$;
    """)

    Repo.query!(
      "CREATE TRIGGER reject_form_copy BEFORE INSERT ON form_integer_constraints FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_form_copy()"
    )

    try do
      assert {:error, _} =
               run(FormVersion, :copy_published, ctx, %{
                 form_id: ctx.form.id,
                 source_version_id: ctx.version.id
               })

      assert Ash.count!(FormVersion, authorize?: false) == 1
      assert Ash.count!(QuestionDefinition, authorize?: false) == 1
      assert run!(FormVersion, :create_draft, ctx, %{form_id: ctx.form.id}).version == 2
    after
      Repo.query!("DROP TRIGGER reject_form_copy ON form_integer_constraints")
    end
  end

  test "later-page invalid definitions are validated and issue output is capped", ctx do
    for n <- 1..101 do
      question =
        Authoring.create(QuestionDefinition, %{
          version_id: ctx.version.id,
          key: "q#{n}",
          prompt: "Private prompt #{n}",
          family: :boolean,
          renderer: :toggle
        })

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
          Authoring.create(InputFieldRequirement, %{
            version_id: ctx.version.id,
            input_slot_id: ctx.slot.id,
            key: "f#{n}",
            value_family: :text,
            required: false
          })

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
