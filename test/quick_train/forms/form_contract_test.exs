defmodule QuickTrain.Forms.FormContractTest do
  alias Ash.Resource.Info, as: ResourceInfo
  use QuickTrain.DataCase, async: true
  import QuickTrain.FormsFixture

  alias QuickTrain.Forms.{FormVersion, Graph}
  alias QuickTrain.Forms.Inputs.{InputFieldRequirement, InputSlotDefinition}
  alias QuickTrain.Forms.Labels.{Label, LabelSet}
  alias QuickTrain.Forms.Presentation.{Heading, PresentationElement, Section}
  alias QuickTrain.Forms.Questions.{InputSource, QuestionDefinition, QuestionOption}

  alias QuickTrain.Forms.Questions.Constraints.{
    AnnotationConstraints,
    DecimalConstraints,
    IntegerConstraints,
    SelectionConstraints,
    TextConstraints
  }

  setup do
    context = context!()
    Map.merge(context, rating!(context))
  end

  for {family, renderer} <- [
        text: :text_area,
        decimal: :decimal_input,
        boolean: :toggle,
        static_single_choice: :radio,
        static_multiple_choice: :checkbox_group,
        task_input_single_choice: :pairwise,
        task_input_multiple_choice: :image_choice,
        task_input_ranking: :ranking,
        bounding_boxes: :bounding_boxes,
        polygon_regions: :polygon_regions,
        raster_masks: :raster_masks,
        text_spans: :text_spans
      ] do
    test "publishes and fully remaps #{family} definitions", ctx do
      family = unquote(family)

      question =
        add!(QuestionDefinition, ctx, ctx.version, %{
          key: "additional",
          prompt: "Question",
          family: family,
          renderer: unquote(renderer)
        })

      build_constraints!(family, question, ctx)

      add!(PresentationElement, ctx, ctx.version, %{
        kind: :question,
        position: 20,
        question_id: question.id
      })

      add!(PresentationElement, ctx, ctx.version, %{
        kind: :instruction,
        position: 21,
        text: "Instructions"
      })

      add!(PresentationElement, ctx, ctx.version, %{kind: :heading, position: 22, text: "Heading"})

      add!(PresentationElement, ctx, ctx.version, %{kind: :section, position: 23, text: ""})

      add!(PresentationElement, ctx, ctx.version, %{
        kind: :bound_value,
        position: 24,
        requirement_id: ctx.field.id
      })

      published = run!(FormVersion, :publish, ctx, %{version_id: ctx.version.id})

      copy =
        run!(FormVersion, :copy_published, ctx, %{
          form_id: ctx.form.id,
          source_version_id: published.id
        })

      assert run!(FormVersion, :publish, ctx, %{version_id: copy.id}).state == :published
      original = Graph.load!(published.id)
      copied = Graph.load!(copy.id)
      source_ids = original |> Map.values() |> List.flatten() |> MapSet.new(& &1.id)

      for resource <- Graph.resources() do
        assert length(original[resource]) == length(copied[resource])

        for row <- copied[resource] do
          refute row.id in source_ids
          assert row.version_id == copy.id

          for relationship <- ResourceInfo.relationships(resource),
              relationship.type == :belongs_to do
            id = Map.fetch!(row, relationship.source_attribute)
            refute id in source_ids
          end
        end
      end

      assert Graph.load!(published.id) == original
    end
  end

  test "blank content and incompatible renderer/family writes fail atomically", ctx do
    for blank <- ["", " \n\t"] do
      assert {:error, _} = edit(QuestionDefinition, ctx, ctx.question, %{prompt: blank})

      for kind <- [:instruction, :heading] do
        assert {:error, _} =
                 run(PresentationElement, :add_to_draft, ctx, %{
                   version_id: ctx.version.id,
                   kind: kind,
                   position: 99,
                   text: blank
                 })
      end
    end

    assert {:error, _} =
             edit(QuestionDefinition, ctx, ctx.question, %{family: :boolean, renderer: :toggle})

    assert {:error, _} = edit(QuestionDefinition, ctx, ctx.question, %{renderer: :text_input})
    assert Ash.get!(QuestionDefinition, ctx.question.id, authorize?: false).family == :integer
    assert Ash.count!(PresentationElement, authorize?: false) == 1
  end

  test "text byte limits apply on create and update including unnamed sections", ctx do
    for {kind, resource} <- [heading: Heading, section: Section] do
      element =
        add!(PresentationElement, ctx, ctx.version, %{
          kind: kind,
          position: 100,
          text: String.duplicate("é", 512)
        })

      child =
        resource
        |> Ash.Query.filter_input(%{element_id: element.id})
        |> Ash.read_one!(authorize?: false)

      assert {:error, _} = edit(resource, ctx, child, %{text: String.duplicate("é", 513)})

      assert {:error, _} =
               run(PresentationElement, :add_to_draft, ctx, %{
                 version_id: ctx.version.id,
                 kind: kind,
                 position: 101,
                 text: String.duplicate("é", 513)
               })

      assert run!(PresentationElement, :remove_from_draft, ctx, %{
               version_id: ctx.version.id,
               id: element.id
             })
    end

    for value <- ["bad" <> <<0>>, <<255>>] do
      assert {:error, _} = edit(QuestionDefinition, ctx, ctx.question, %{prompt: value})
    end
  end

  test "every integer contract rejects overflow while scalar endpoints remain representable",
       ctx do
    assert {:ok, _} = edit(QuestionDefinition, ctx, ctx.question, %{renderer: :integer_input})

    assert {:ok, _} =
             edit(IntegerConstraints, ctx, ctx.bounds, %{
               minimum: -2_147_483_648,
               maximum: 2_147_483_647
             })

    for attrs <- [
          %{minimum: -2_147_483_649},
          %{maximum: 2_147_483_648},
          %{minimum: 8, maximum: 2}
        ] do
      assert {:error, _} = edit(IntegerConstraints, ctx, ctx.bounds, attrs)
    end

    assert {:error, _} = edit(PresentationElement, ctx, ctx.element, %{position: 2_147_483_648})

    for attrs <- [%{minimum: 0}, %{maximum: 101}, %{minimum: 3, maximum: 2}] do
      assert {:error, _} = edit(InputSlotDefinition, ctx, ctx.slot, attrs)
    end

    question =
      add!(QuestionDefinition, ctx, ctx.version, %{
        key: "text",
        prompt: "Text",
        family: :text,
        renderer: :text_input
      })

    constraints =
      add!(TextConstraints, ctx, ctx.version, %{question_id: question.id, maximum: 2_147_483_647})

    assert {:error, _} = edit(TextConstraints, ctx, constraints, %{maximum: 2_147_483_648})
  end

  test "stars and Likert require explicit bounds and at most 200 values", ctx do
    for renderer <- [:stars, :likert] do
      assert {:ok, _} = edit(QuestionDefinition, ctx, ctx.question, %{renderer: renderer})

      assert {:ok, bounds} =
               edit(IntegerConstraints, ctx, ctx.bounds, %{minimum: nil, maximum: nil})

      assert {:error, _} = run(FormVersion, :publish, ctx, %{version_id: ctx.version.id})
      assert {:error, _} = edit(IntegerConstraints, ctx, bounds, %{minimum: 0, maximum: 200})
      assert {:ok, _} = edit(IntegerConstraints, ctx, bounds, %{minimum: 1, maximum: 200})
    end

    assert run!(FormVersion, :publish, ctx, %{version_id: ctx.version.id}).state == :published
  end

  test "asset intent, cardinality, UTC naming and inbound source compatibility", ctx do
    for attrs <- [%{intended_use: :image}, %{cardinality: :many}, %{value_family: :datetime}] do
      assert {:error, _} = edit(InputFieldRequirement, ctx, ctx.field, attrs)
    end

    assert {:ok, _} = edit(InputFieldRequirement, ctx, ctx.field, %{value_family: :utc_datetime})

    image =
      add!(InputFieldRequirement, ctx, ctx.version, %{
        key: "image",
        input_slot_id: ctx.slot.id,
        value_family: :asset,
        intended_use: :image,
        required: true
      })

    assert {:error, _} = edit(InputFieldRequirement, ctx, image, %{value_family: :text})
    labels = labels!(ctx)

    question =
      add!(QuestionDefinition, ctx, ctx.version, %{
        key: "regions",
        prompt: "Regions",
        family: :bounding_boxes,
        renderer: :bounding_boxes
      })

    bounds =
      add!(AnnotationConstraints, ctx, ctx.version, %{
        question_id: question.id,
        source_requirement_id: image.id,
        label_set_id: labels.id,
        minimum: 0,
        maximum: 2_147_483_647
      })

    for attrs <- [
          %{intended_use: :download},
          %{required: false},
          %{value_family: :text, intended_use: nil}
        ] do
      assert {:error, _} = edit(InputFieldRequirement, ctx, image, attrs)
    end

    assert {:error, _} = edit(AnnotationConstraints, ctx, bounds, %{maximum: 2_147_483_648})
  end

  test "reorder requires a complete scoped permutation and canonicalizes gaps", ctx do
    second =
      add!(PresentationElement, ctx, ctx.version, %{kind: :section, position: 200, text: ""})

    for ids <- [[second.id], [second.id, second.id], [second.id, Ash.UUID.generate()]] do
      assert {:error, _} =
               run(PresentationElement, :reorder, ctx, %{version_id: ctx.version.id, ids: ids})
    end

    assert run!(PresentationElement, :reorder, ctx, %{
             version_id: ctx.version.id,
             ids: [second.id, ctx.element.id]
           })

    assert Ash.get!(PresentationElement, second.id, authorize?: false).position == 0
    assert Ash.get!(PresentationElement, ctx.element.id, authorize?: false).position == 1

    assert {:error, _} =
             run(QuestionOption, :reorder, ctx, %{
               version_id: ctx.version.id,
               question_id: Ash.UUID.generate(),
               ids: []
             })

    assert {:error, _} =
             run(Label, :reorder, ctx, %{
               version_id: ctx.version.id,
               label_set_id: Ash.UUID.generate(),
               ids: []
             })
  end

  test "foreign references and referenced deletion leave the graph intact", ctx do
    other = draft!(ctx, "other")

    foreign =
      add!(InputSlotDefinition, ctx, other.version, %{key: "foreign", minimum: 1, maximum: 1})

    assert {:error, _} =
             run(InputFieldRequirement, :add_to_draft, ctx, %{
               version_id: ctx.version.id,
               input_slot_id: foreign.id,
               key: "cross",
               value_family: :text,
               required: true
             })

    assert {:error, _} =
             run(QuestionDefinition, :remove_from_draft, ctx, %{
               version_id: ctx.version.id,
               id: ctx.question.id
             })

    assert {:error, _} =
             run(FormVersion, :copy_published, ctx, %{
               form_id: ctx.form.id,
               source_version_id: ctx.version.id
             })

    assert run!(FormVersion, :create_draft, ctx, %{form_id: ctx.form.id}).version == 2
  end

  test "blank titles and foreign published copy sources fail without consuming numbers", ctx do
    for title <- [nil, "", " \n\t"] do
      run!(FormVersion, :update_draft, ctx, %{version_id: ctx.version.id, title: title})
      assert {:error, error} = run(FormVersion, :publish, ctx, %{version_id: ctx.version.id})
      assert Exception.message(error) =~ "title is required"
    end

    run!(FormVersion, :update_draft, ctx, %{version_id: ctx.version.id, title: "Ready"})
    published = run!(FormVersion, :publish, ctx, %{version_id: ctx.version.id})
    other = draft!(ctx, "other-form")

    assert {:error, _} =
             run(FormVersion, :copy_published, ctx, %{
               form_id: other.form.id,
               source_version_id: published.id
             })

    assert run!(FormVersion, :create_draft, ctx, %{form_id: other.form.id}).version == 2
  end

  defp build_constraints!(:text, question, ctx),
    do:
      add!(TextConstraints, ctx, ctx.version, %{question_id: question.id, minimum: 0, maximum: 10})

  defp build_constraints!(:decimal, question, ctx),
    do:
      add!(DecimalConstraints, ctx, ctx.version, %{
        question_id: question.id,
        minimum: "0.000000000000000001",
        maximum: "9.999999999999999999"
      })

  defp build_constraints!(:boolean, _question, _ctx), do: :ok

  defp build_constraints!(family, question, ctx)
       when family in [:static_single_choice, :static_multiple_choice] do
    add!(SelectionConstraints, ctx, ctx.version, %{
      question_id: question.id,
      minimum: 1,
      maximum: 1
    })

    for n <- 1..2,
        do:
          add!(QuestionOption, ctx, ctx.version, %{
            question_id: question.id,
            key: "option#{n}",
            label: "Option #{n}",
            position: n
          })
  end

  defp build_constraints!(family, question, ctx)
       when family in [
              :task_input_single_choice,
              :task_input_multiple_choice,
              :task_input_ranking
            ] do
    slot =
      add!(InputSlotDefinition, ctx, ctx.version, %{key: "candidates", minimum: 2, maximum: 2})

    field =
      add!(InputFieldRequirement, ctx, ctx.version, %{
        key: "image",
        input_slot_id: slot.id,
        value_family: :asset,
        intended_use: :image,
        required: true
      })

    source = if question.renderer == :image_choice, do: field.id

    add!(InputSource, ctx, ctx.version, %{
      question_id: question.id,
      input_slot_id: slot.id,
      source_requirement_id: source
    })

    unless family == :task_input_ranking,
      do:
        add!(SelectionConstraints, ctx, ctx.version, %{
          question_id: question.id,
          minimum: 1,
          maximum: 1
        })
  end

  defp build_constraints!(family, question, ctx) do
    source =
      if family == :text_spans,
        do: ctx.field,
        else:
          add!(InputFieldRequirement, ctx, ctx.version, %{
            key: "image",
            input_slot_id: ctx.slot.id,
            value_family: :asset,
            intended_use: :image,
            required: true
          })

    set = labels!(ctx)

    add!(AnnotationConstraints, ctx, ctx.version, %{
      question_id: question.id,
      source_requirement_id: source.id,
      label_set_id: set.id,
      minimum: 0,
      maximum: 10
    })
  end

  defp labels!(ctx) do
    set = add!(LabelSet, ctx, ctx.version, %{key: "labels"})

    add!(Label, ctx, ctx.version, %{
      label_set_id: set.id,
      key: "label",
      text: "Label",
      position: 0
    })

    set
  end
end
