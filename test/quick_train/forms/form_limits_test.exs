defmodule QuickTrain.Forms.FormLimitsTest do
  use QuickTrain.DataCase, async: true
  import QuickTrain.FormsFixture

  alias QuickTrain.Forms.{
    Authoring,
    FormVersion,
    Graph,
    InputSlotDefinition,
    Label,
    LabelSet,
    QuestionDefinition,
    QuestionOption,
    SelectionConstraints
  }

  setup do
    ctx = context!()
    Map.merge(ctx, rating!(ctx))
  end

  test "option and label text and full-permutation ordering are enforced", ctx do
    question =
      add!(QuestionDefinition, ctx, ctx.version, %{
        key: "choice",
        prompt: "Choose",
        family: :static_single_choice,
        renderer: :radio
      })

    set = add!(LabelSet, ctx, ctx.version, %{key: "labels"})

    for {resource, parent, field} <- [
          {QuestionOption, %{question_id: question.id}, :label},
          {Label, %{label_set_id: set.id}, :text}
        ] do
      for blank <- ["", " \t"] do
        assert {:error, _} =
                 run(
                   resource,
                   :add_to_draft,
                   ctx,
                   Map.merge(parent, %{
                     field => blank,
                     version_id: ctx.version.id,
                     key: "blank",
                     position: 0
                   })
                 )
      end

      records =
        for n <- [10, 100],
            do:
              add!(
                resource,
                ctx,
                ctx.version,
                Map.merge(parent, %{field => "Visible", key: "key#{n}", position: n})
              )

      for record <- records do
        assert {:error, _} = edit(resource, ctx, record, %{field => " "})
      end

      ids = Enum.map(Enum.reverse(records), & &1.id)

      assert run!(
               resource,
               :reorder,
               ctx,
               Map.merge(parent, %{version_id: ctx.version.id, ids: ids})
             )

      assert Enum.map(ids, &Ash.get!(resource, &1, authorize?: false).position) == [0, 1]
    end

    assert {:error, _} =
             run(QuestionOption, :add_to_draft, ctx, %{
               version_id: ctx.version.id,
               question_id: ctx.question.id,
               key: "wrong",
               label: "Wrong",
               position: 0
             })

    assert {:error, _} =
             run(SelectionConstraints, :add_to_draft, ctx, %{
               version_id: ctx.version.id,
               question_id: question.id,
               minimum: 1,
               maximum: 2
             })
  end

  test "version exhaustion fails without wrapping or creating a destination", ctx do
    Authoring.create(FormVersion, %{form_id: ctx.form.id, version: 2_147_483_647})
    assert {:error, _} = run(FormVersion, :create_draft, ctx, %{form_id: ctx.form.id})
    assert Ash.count!(FormVersion, authorize?: false) == 2
  end

  test "10000 owned rows are allowed and the next authoring write rolls back", ctx do
    for n <- 1..50 do
      set = Authoring.create(LabelSet, %{version_id: ctx.version.id, key: "set#{n}"})
      count = if n == 50, do: 144, else: 200

      rows =
        for position <- 1..count,
            do: %{
              version_id: ctx.version.id,
              label_set_id: set.id,
              key: "l#{position}",
              text: "Label",
              position: position
            }

      Ash.bulk_create!(rows, Label, :create_internal, authorize?: false)
    end

    assert Enum.sum(
             Enum.map(Graph.load!(ctx.version.id), fn {_resource, rows} -> length(rows) end)
           ) == 10_000

    assert {:error, _} =
             run(InputSlotDefinition, :add_to_draft, ctx, %{
               version_id: ctx.version.id,
               key: "overflow",
               minimum: 1,
               maximum: 1
             })

    assert Ash.count!(InputSlotDefinition, authorize?: false) == 1
    assert run!(FormVersion, :publish, ctx, %{version_id: ctx.version.id}).state == :published

    copied =
      run!(FormVersion, :copy_published, ctx, %{
        form_id: ctx.form.id,
        source_version_id: ctx.version.id
      })

    assert Enum.sum(Enum.map(Graph.load!(copied.id), fn {_resource, rows} -> length(rows) end)) ==
             10_000
  end
end
