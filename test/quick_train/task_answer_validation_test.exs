defmodule QuickTrain.Tasks.AnswerInputTest do
  use ExUnit.Case, async: true

  alias QuickTrain.Tasks.Responses.AnswerValidation
  alias QuickTrain.Tasks.Responses.Inputs.AnswerInput

  test "validation rejects a task outside the pinned project before reading its contract" do
    project = %{id: "project", organization_id: "organization", form_version_id: "version"}
    task = %{project_id: "foreign", organization_id: "organization", form_version_id: "version"}
    question = %{id: "question", version_id: "version", family: :text, input_slot_id: nil}

    assert_raise Ash.Error.Invalid, fn ->
      AnswerValidation.validate!(project, task, question, %{}, :draft)
    end
  end

  test "typed input preserves exact Unicode and decimal values" do
    assert {:ok, answer} =
             Ash.Type.cast_input(AnswerInput, %{
               outcome: :answered,
               family: :text,
               text_value: "  é😀\n"
             })

    assert answer.text_value == "  é😀\n"

    assert {:ok, answer} =
             Ash.Type.cast_input(AnswerInput, %{
               outcome: :answered,
               family: :decimal,
               decimal_value: "123456789.123456789123456789"
             })

    assert Decimal.equal?(answer.decimal_value, Decimal.new("123456789.123456789123456789"))
  end

  test "typed input rejects unsupported fields invalid UUID children and non-finite decimals" do
    for input <- [
          %{outcome: :answered, family: :text, arbitrary_payload: %{}},
          %{outcome: :answered, family: :integer, integer_value: 2_147_483_648},
          %{outcome: :answered, family: :decimal, decimal_value: "NaN"},
          %{outcome: :answered, family: :decimal, decimal_value: "Infinity"},
          %{outcome: :answered, family: :static_single_choice, option_ids: ["foreign"]},
          %{outcome: :answered, family: :text_spans, spans: [%{task_input_id: "bad"}]}
        ] do
      assert {:error, _} = Ash.Type.cast_input(AnswerInput, input)
    end
  end
end

defmodule QuickTrain.Tasks.AnswerValidationTest do
  use QuickTrain.DataCase, async: false
  @moduletag :integration

  alias QuickTrain.{Datasets, Forms, FormsFixture, Projects}
  alias QuickTrain.Forms.Inputs.{InputFieldRequirement, InputSlotDefinition}
  alias QuickTrain.Forms.Labels.{Label, LabelSet}
  alias QuickTrain.Forms.Presentation.PresentationElement
  alias QuickTrain.Forms.Questions.{QuestionDefinition, QuestionOption}

  alias QuickTrain.Forms.Questions.Constraints.{
    AnnotationConstraints,
    DecimalConstraints,
    IntegerConstraints,
    SelectionConstraints,
    TextConstraints
  }

  alias QuickTrain.Tasks.Responses.AnswerValidation
  alias QuickTrain.Tasks.{Task, TaskInput}
  require Ash.Query

  setup do
    context =
      FormsFixture.context!(
        ~w(forms.read forms.manage projects.manage datasets.read datasets.manage),
        "answer-#{System.unique_integer([:positive])}"
      )

    form = FormsFixture.draft!(context)

    slot =
      FormsFixture.add!(InputSlotDefinition, context, form.version, %{
        key: "items",
        minimum: 2,
        maximum: 3
      })

    other_slot =
      FormsFixture.add!(InputSlotDefinition, context, form.version, %{
        key: "other",
        minimum: 1,
        maximum: 1
      })

    requirement =
      FormsFixture.add!(InputFieldRequirement, context, form.version, %{
        input_slot_id: slot.id,
        key: "body",
        value_family: :text,
        required: true
      })

    FormsFixture.add!(InputFieldRequirement, context, form.version, %{
      input_slot_id: other_slot.id,
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

    other_labels =
      FormsFixture.add!(LabelSet, context, form.version, %{key: "other", name: "Other"})

    other_label =
      FormsFixture.add!(Label, context, form.version, %{
        label_set_id: other_labels.id,
        key: "other",
        text: "Other",
        position: 0
      })

    base =
      Map.merge(form, %{
        context: context,
        slot: slot,
        other_slot: other_slot,
        requirement: requirement,
        labels: labels,
        label: label,
        other_label: other_label
      })

    %{base: base}
  end

  test "absent scalar constraints retain defaults and exact text decimal and boolean values", %{
    base: base
  } do
    text = question!(base, :text)
    integer = question!(base, :integer)
    decimal = question!(base, :decimal)
    boolean = question!(base, :boolean)
    scope = publish!(base)
    assert validate!(scope, text, %{text_value: "  é😀\n"}).attributes.text_value == "  é😀\n"
    assert validate!(scope, text, %{text_value: ""}).attributes.text_value == ""

    for endpoint <- [-2_147_483_648, 2_147_483_647],
        do:
          assert(
            validate!(scope, integer, %{integer_value: endpoint}).attributes.integer_value ==
              endpoint
          )

    assert Decimal.equal?(
             validate!(scope, decimal, %{decimal_value: "-987654321.123456789123456789"}).attributes.decimal_value,
             Decimal.new("-987654321.123456789123456789")
           )

    assert validate!(scope, boolean, %{boolean_value: false}).attributes.boolean_value == false
  end

  test "empty scalar constraint records preserve the same published defaults as absent records",
       %{base: base} do
    text = question!(base, :text, %{minimum: nil, maximum: nil})
    integer = question!(base, :integer, %{minimum: nil, maximum: nil})
    decimal = question!(base, :decimal, %{minimum: nil, maximum: nil})
    scope = publish!(base)

    assert validate!(scope, text, %{text_value: ""}).attributes.text_value == ""

    assert validate!(scope, integer, %{integer_value: -2_147_483_648}).attributes.integer_value ==
             -2_147_483_648

    assert validate!(scope, decimal, %{decimal_value: "-0.000000000000000001"}).attributes.decimal_value ==
             Decimal.new("-0.000000000000000001")
  end

  test "draft scalar incompleteness is allowed but supplied values obey published bounds", %{
    base: base
  } do
    text = question!(base, :text, %{minimum: 2, maximum: 3})
    integer = question!(base, :integer, %{minimum: 1, maximum: 5})

    decimal =
      question!(base, :decimal, %{
        minimum: "0.123456789123456789",
        maximum: "0.123456789123456790"
      })

    scope = publish!(base)
    assert validate!(scope, integer, %{}, :draft).attributes.integer_value == nil
    assert_raise Ash.Error.Invalid, fn -> validate!(scope, integer, %{}) end
    assert validate!(scope, text, %{text_value: "é😀"}, :draft).attributes.text_value == "é😀"

    for {question, payload} <- [
          {text, %{text_value: "e"}},
          {text, %{text_value: "é😀x"}},
          {integer, %{integer_value: 0}},
          {decimal, %{decimal_value: "0.123456789123456788"}}
        ] do
      assert_raise Ash.Error.Invalid, fn -> validate!(scope, question, payload, :draft) end
    end
  end

  test "wrong-family mixed payload invalid Unicode and NUL fail even in drafts", %{base: base} do
    question = question!(base, :text)
    scope = publish!(base)

    for payload <- [
          %{family: :integer, integer_value: 3},
          %{text_value: "yes", boolean_value: false},
          %{text_value: "yes", option_ids: [base.label.id]},
          %{text_value: <<255>>},
          %{text_value: "a\0b"}
        ] do
      assert_raise Ash.Error.Invalid, fn -> validate!(scope, question, payload, :draft) end
    end
  end

  test "skips retain reason and explanation but accept no scalar or child payload", %{base: base} do
    question = question!(base, :text)
    scope = publish!(base)

    result =
      validate!(
        scope,
        question,
        %{outcome: :skipped, reason: "  unavailable  ", explanation: "more\n"},
        :draft
      )

    assert result.attributes.reason == "  unavailable  "
    assert %DateTime{} = result.attributes.skipped_at
    assert result.option_ids == [] and result.inputs == [] and result.spans == []

    for payload <- [%{text_value: ""}, %{option_ids: [base.label.id]}, %{reason: "  "}] do
      assert_raise Ash.Error.Invalid, fn ->
        validate!(scope, question, Map.put(payload, :outcome, :skipped), :draft)
      end
    end
  end

  test "static choices enforce ownership uniqueness and stage-specific count bounds", %{
    base: base
  } do
    single = question!(base, :static_single_choice)
    multiple = question!(base, :static_multiple_choice, %{minimum: 2, maximum: 2})
    scope = publish!(base)
    [one, two] = options(multiple)
    [foreign, other] = options(single)
    assert validate!(scope, multiple, %{option_ids: [one.id]}, :draft).option_ids == [one.id]

    assert validate!(scope, multiple, %{option_ids: [one.id, two.id]}).option_ids == [
             one.id,
             two.id
           ]

    for {question, ids, stage} <- [
          {multiple, [one.id], :submit},
          {multiple, [one.id, one.id], :draft},
          {multiple, [one.id, foreign.id], :draft},
          {single, [], :submit},
          {single, [foreign.id, other.id], :draft},
          {single, [one.id], :draft}
        ] do
      assert_raise Ash.Error.Invalid, fn ->
        validate!(scope, question, %{option_ids: ids}, stage)
      end
    end
  end

  test "task-input choices and rankings use exact task and slot membership", %{base: base} do
    single = question!(base, :task_input_single_choice)
    multiple = question!(base, :task_input_multiple_choice, %{minimum: 2, maximum: 2})
    ranking = question!(base, :task_input_ranking)
    scope = collection!(publish!(base))
    [one, two] = scope.inputs

    assert validate!(scope, single, %{inputs: [%{task_input_id: one.id}]}).inputs == [
             %{task_input_id: one.id, position: nil}
           ]

    assert validate!(scope, multiple, %{inputs: [%{task_input_id: one.id}]}, :draft).inputs == [
             %{task_input_id: one.id, position: nil}
           ]

    ordered = [%{task_input_id: two.id, position: 0}, %{task_input_id: one.id, position: 1}]
    assert validate!(scope, ranking, %{inputs: [hd(ordered)]}, :draft).inputs == [hd(ordered)]
    assert validate!(scope, ranking, %{inputs: ordered}).inputs == ordered

    for {question, inputs, stage} <- [
          {single, [%{task_input_id: scope.other_input.id}], :draft},
          {single, [%{task_input_id: scope.foreign_input.id}], :draft},
          {multiple, [%{task_input_id: one.id}], :submit},
          {ranking, [hd(ordered)], :submit},
          {ranking,
           [%{task_input_id: one.id, position: 0}, %{task_input_id: one.id, position: 1}],
           :draft},
          {ranking,
           [%{task_input_id: one.id, position: 0}, %{task_input_id: two.id, position: 0}], :draft}
        ] do
      assert_raise Ash.Error.Invalid, fn ->
        validate!(scope, question, %{inputs: inputs}, stage)
      end
    end
  end

  test "text spans count code points allow overlap and reject duplicates and foreign provenance",
       %{base: base} do
    question = question!(base, :text_spans, %{minimum: 1, maximum: 3})
    scope = collection!(publish!(base))
    [input | _] = scope.inputs

    span = %{
      task_input_id: input.id,
      source_value_id: scope.source_value.id,
      label_id: base.label.id,
      start: 1,
      end: 5
    }

    overlap = %{span | start: 3, end: 4}
    assert validate!(scope, question, %{spans: [span, overlap]}).spans == [span, overlap]
    assert validate!(scope, question, %{spans: []}, :draft).spans == []

    [_first_input, other_input] = scope.inputs

    for spans <- [
          [],
          [span, span],
          [%{span | start: 5, end: 6}],
          [%{span | start: 1, end: 1}],
          [%{span | start: -1}],
          [%{span | label_id: base.other_label.id}],
          [%{span | source_value_id: scope.other_value.id}],
          [%{span | task_input_id: other_input.id}],
          [%{span | task_input_id: scope.foreign_input.id}]
        ] do
      assert_raise Ash.Error.Invalid, fn -> validate!(scope, question, %{spans: spans}) end
    end

    assert_raise Ash.Error.Invalid, fn ->
      validate!(
        scope,
        question,
        %{spans: [span, overlap, %{span | start: 0}, %{span | end: 4}]},
        :draft
      )
    end
  end

  test "zero text spans is answered when the published minimum is zero", %{base: base} do
    question = question!(base, :text_spans, %{minimum: 0, maximum: 1})
    scope = collection!(publish!(base))
    assert validate!(scope, question, %{spans: []}).attributes.outcome == :answered
  end

  defp question!(base, family, bounds \\ nil) do
    renderer =
      %{
        text: :text_input,
        integer: :integer_input,
        decimal: :decimal_input,
        boolean: :checkbox,
        static_single_choice: :radio,
        static_multiple_choice: :checkbox_group,
        task_input_single_choice: :radio,
        task_input_multiple_choice: :checkbox_group,
        task_input_ranking: :ranking,
        text_spans: :text_spans
      }[family]

    attrs = %{key: Atom.to_string(family), prompt: "Answer", family: family, renderer: renderer}

    attrs =
      if family in [
           :task_input_single_choice,
           :task_input_multiple_choice,
           :task_input_ranking
         ], do: Map.put(attrs, :input_slot_id, base.slot.id), else: attrs

    question = FormsFixture.add!(QuestionDefinition, base.context, base.version, attrs)

    FormsFixture.add!(PresentationElement, base.context, base.version, %{
      kind: :question,
      position: System.unique_integer([:positive]),
      question_id: question.id
    })

    resource =
      %{
        text: TextConstraints,
        integer: IntegerConstraints,
        decimal: DecimalConstraints,
        static_single_choice: SelectionConstraints,
        static_multiple_choice: SelectionConstraints,
        task_input_single_choice: SelectionConstraints,
        task_input_multiple_choice: SelectionConstraints,
        text_spans: AnnotationConstraints
      }[family]

    bounds =
      if family in [:static_single_choice, :task_input_single_choice],
        do: %{minimum: 1, maximum: 1},
        else: bounds

    if bounds do
      attrs = Map.put(bounds, :question_id, question.id)

      attrs =
        if family == :text_spans,
          do:
            Map.merge(attrs, %{
              source_requirement_id: base.requirement.id,
              label_set_id: base.labels.id
            }),
          else: attrs

      FormsFixture.add!(resource, base.context, base.version, attrs)
    end

    if family in [:static_single_choice, :static_multiple_choice] do
      for position <- 0..1,
          do:
            FormsFixture.add!(QuestionOption, base.context, base.version, %{
              question_id: question.id,
              key: "option-#{position}",
              label: "Option #{position}",
              position: position
            })
    end

    question
  end

  defp publish!(base) do
    version =
      Forms.publish_form_version!(base.context.org.id, %{version_id: base.version.id},
        actor: base.context.actor
      )

    project = %{
      id: base.form.id,
      organization_id: base.context.org.id,
      form_version_id: version.id
    }

    task = %{
      id: base.slot.id,
      project_id: project.id,
      organization_id: project.organization_id,
      form_version_id: version.id
    }

    Map.merge(base, %{version: version, project: project, task: task})
  end

  defp collection!(base) do
    context = base.context
    dataset = Datasets.create_dataset!(context.org.id, "data", "Data", actor: context.actor)
    schema = Datasets.create_schema_version!(context.org.id, dataset.id, actor: context.actor)

    root =
      Datasets.add_record_type!(context.org.id, schema.id, "item", "Item", actor: context.actor)

    body =
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

    other =
      Datasets.add_field_definition!(
        context.org.id,
        root.id,
        "other",
        "Other",
        "text",
        "single",
        true,
        actor: context.actor
      )

    schema =
      Datasets.publish_schema_version!(context.org.id, schema.id, root.id, actor: context.actor)

    revisions =
      for n <- 1..3,
          do:
            Datasets.put_item_revision!(
              context.org.id,
              dataset.id,
              schema.id,
              nil,
              "item-#{n}",
              [%{field: "body", text: "A😀éZ"}, %{field: "other", text: "wrong source"}],
              actor: context.actor
            ).revision

    project =
      Projects.create_project!(
        context.org.id,
        %{
          title: "Answers",
          dataset_id: dataset.id,
          schema_version_id: schema.id,
          form_version_id: base.version.id
        },
        actor: context.actor
      )

    create!(QuickTrain.Projects.ProjectInputBinding, %{
      project_id: project.id,
      schema_version_id: schema.id,
      root_record_type_id: root.id,
      form_version_id: base.version.id,
      requirement_id: base.requirement.id,
      field_definition_id: body.id
    })

    task_attrs = %{
      organization_id: context.org.id,
      project_id: project.id,
      form_version_id: base.version.id,
      explicit_group_id:
        create!(QuickTrain.Projects.ExplicitGroup, %{
          project_id: project.id,
          form_version_id: base.version.id,
          position: 0,
          canonical_key: <<1>>
        }).id
    }

    task = create!(Task, task_attrs)

    foreign_task =
      create!(Task, %{
        task_attrs
        | explicit_group_id:
            create!(QuickTrain.Projects.ExplicitGroup, %{
              project_id: project.id,
              form_version_id: base.version.id,
              position: 1,
              canonical_key: <<2>>
            }).id
      })

    inputs =
      for {revision, index} <- Enum.with_index(revisions) do
        item =
          create!(QuickTrain.Projects.ProjectItem, %{
            project_id: project.id,
            dataset_id: dataset.id,
            schema_version_id: schema.id,
            item_id: revision.item_id,
            revision_id: revision.id
          })

        attrs = %{
          organization_id: context.org.id,
          project_id: project.id,
          form_version_id: base.version.id,
          task_id: task.id,
          project_item_id: item.id,
          revision_id: revision.id,
          input_slot_id: if(index < 2, do: base.slot.id, else: base.other_slot.id)
        }

        input = create!(TaskInput, attrs)

        foreign =
          if index == 0, do: create!(TaskInput, %{attrs | task_id: foreign_task.id}), else: nil

        {input, foreign}
      end

    [{one, foreign}, {two, _}, {other_input, _}] = inputs

    value = fn field ->
      QuickTrain.Datasets.DatasetValue
      |> Ash.Query.filter(
        record_id == ^hd(revisions).root_record_id and field_definition_id == ^field.id
      )
      |> Ash.read_one!(authorize?: false)
    end

    Map.merge(base, %{
      project: project,
      task: task,
      inputs: [one, two],
      other_input: other_input,
      foreign_input: foreign,
      source_value: value.(body),
      other_value: value.(other)
    })
  end

  defp create!(resource, attrs),
    do:
      resource
      |> Ash.Changeset.for_create(:create_internal, attrs)
      |> Ash.create!(authorize?: false)

  defp options(question),
    do:
      QuestionOption
      |> Ash.Query.filter(question_id == ^question.id)
      |> Ash.read!(authorize?: false, page: false)

  defp validate!(scope, question, attrs, stage \\ :submit),
    do:
      AnswerValidation.validate!(
        scope.project,
        scope.task,
        question,
        Map.merge(%{outcome: :answered, family: question.family}, attrs),
        stage
      )
end
