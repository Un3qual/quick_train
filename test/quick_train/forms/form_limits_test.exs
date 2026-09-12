defmodule QuickTrain.Forms.FormLimitsTest do
  use QuickTrain.DataCase, async: true
  import QuickTrain.FormsFixture

  alias QuickTrain.Forms.{FormVersion, Graph}
  alias QuickTrain.Forms.Inputs.InputSlotDefinition
  alias QuickTrain.Forms.Labels.{Label, LabelSet}
  alias QuickTrain.Forms.Questions.Constraints.SelectionConstraints
  alias QuickTrain.Forms.Questions.{QuestionDefinition, QuestionOption}

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

      assert {:error, %Ash.Error.Invalid{errors: errors}} =
               run(
                 resource,
                 :add_to_draft,
                 ctx,
                 Map.merge(parent, %{
                   field => "Collision",
                   key: "collision",
                   position: 10,
                   version_id: ctx.version.id
                 })
               )

      assert Enum.any?(errors, &match?(%Ash.Error.Changes.InvalidAttribute{field: :position}, &1))

      [_, second] = records

      assert {:error, %Ash.Error.Invalid{errors: errors}} =
               edit(resource, ctx, second, %{position: 10})

      assert Enum.any?(errors, &match?(%Ash.Error.Changes.InvalidAttribute{field: :position}, &1))
      assert Ash.get!(resource, second.id, authorize?: false).position == 100

      ids = Enum.map(Enum.reverse(records), & &1.id)

      for order <- [ids, Enum.reverse(ids)] do
        assert run!(
                 resource,
                 :reorder,
                 ctx,
                 Map.merge(parent, %{version_id: ctx.version.id, ids: order})
               )

        assert Enum.map(order, &Ash.get!(resource, &1, authorize?: false).position) == [0, 1]
      end
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
    Ash.Seed.seed!(FormVersion, %{form_id: ctx.form.id, version: 2_147_483_647})

    assert {:error, _} = run(FormVersion, :create_draft, ctx, %{form_id: ctx.form.id})
    assert Ash.count!(FormVersion, authorize?: false) == 2
  end

  test "10000 owned rows are allowed and the next authoring write rolls back", ctx do
    for n <- 1..50 do
      set =
        Ash.create!(LabelSet, %{version_id: ctx.version.id, key: "set#{n}"},
          action: :create_internal,
          authorize?: false
        )

      count = if n == 50, do: 10_000 - graph_size(ctx.version.id), else: 200

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

    assert graph_size(ctx.version.id) == 10_000

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

    assert graph_size(copied.id) == 10_000
  end

  defp graph_size(version_id),
    do: Enum.sum(Enum.map(Graph.load!(version_id), fn {_resource, rows} -> length(rows) end))
end
