defmodule QuickTrain.Forms.Graph do
  alias Ash.Resource.Info, as: ResourceInfo
  @moduledoc false
  alias QuickTrain.Forms.Error
  alias QuickTrain.Forms.Inputs.{InputFieldRequirement, InputSlotDefinition}
  alias QuickTrain.Forms.Labels.{Label, LabelSet}

  alias QuickTrain.Forms.Presentation.{
    BoundValue,
    Heading,
    Instruction,
    PresentationElement,
    QuestionPlacement,
    Section
  }

  alias QuickTrain.Forms.Questions.{InputSource, QuestionDefinition, QuestionOption}

  alias QuickTrain.Forms.Questions.Constraints.{
    AnnotationConstraints,
    DecimalConstraints,
    IntegerConstraints,
    SelectionConstraints,
    TextConstraints
  }

  require Ash.Query

  @resources [
    InputSlotDefinition,
    InputFieldRequirement,
    LabelSet,
    Label,
    QuestionDefinition,
    TextConstraints,
    IntegerConstraints,
    DecimalConstraints,
    SelectionConstraints,
    AnnotationConstraints,
    InputSource,
    QuestionOption,
    PresentationElement,
    Instruction,
    Heading,
    Section,
    BoundValue,
    QuestionPlacement
  ]
  @presentations %{
    instruction: Instruction,
    heading: Heading,
    section: Section,
    bound_value: BoundValue,
    question: QuestionPlacement
  }
  @renderers %{
    text: [:text_input, :text_area],
    integer: [:integer_input, :stars, :likert],
    decimal: [:decimal_input],
    boolean: [:checkbox, :toggle],
    static_single_choice: [:radio, :dropdown],
    static_multiple_choice: [:checkbox_group],
    task_input_single_choice: [:radio, :dropdown, :pairwise, :image_choice],
    task_input_multiple_choice: [:checkbox_group, :image_choice],
    task_input_ranking: [:ranking],
    bounding_boxes: [:bounding_boxes],
    polygon_regions: [:polygon_regions],
    raster_masks: [:raster_masks],
    text_spans: [:text_spans]
  }
  @constraints %{
    text: TextConstraints,
    integer: IntegerConstraints,
    decimal: DecimalConstraints,
    static_single_choice: SelectionConstraints,
    static_multiple_choice: SelectionConstraints,
    task_input_single_choice: SelectionConstraints,
    task_input_multiple_choice: SelectionConstraints,
    bounding_boxes: AnnotationConstraints,
    polygon_regions: AnnotationConstraints,
    raster_masks: AnnotationConstraints,
    text_spans: AnnotationConstraints
  }
  @constraint_resources @constraints |> Map.values() |> Enum.uniq()
  @static [:static_single_choice, :static_multiple_choice]
  @dynamic [:task_input_single_choice, :task_input_multiple_choice, :task_input_ranking]
  @single [:static_single_choice, :task_input_single_choice]
  @limits [
    {InputSlotDefinition, :version_id, 32},
    {InputFieldRequirement, :input_slot_id, 64},
    {QuestionDefinition, :version_id, 200},
    {PresentationElement, :version_id, 1000},
    {QuestionOption, :question_id, 200},
    {LabelSet, :version_id, 100},
    {Label, :label_set_id, 200}
  ]

  def resources, do: @resources

  def load!(version_id) do
    {graph, _count} =
      Enum.reduce(@resources, {%{}, 0}, fn resource, {graph, count} ->
        records =
          resource
          |> Ash.Query.filter(version_id == ^version_id)
          |> Ash.Query.limit(10_001 - count)
          |> Ash.read!(authorize?: false, page: false)

        count = count + length(records)
        if count > 10_000, do: Error.reject!(:graph_limit_exceeded)
        {Map.put(graph, resource, records), count}
      end)

    graph
  end

  def validate!(version, state) do
    graph = load!(version.id)

    issues =
      limit_issues(graph) ++
        local_issues(graph, state) ++ publication_issues(graph, version, state)

    if issues != [], do: Error.reject!(:invalid_form_contract, issues)
    graph
  end

  defp limit_issues(graph) do
    Enum.flat_map(@limits, fn {resource, parent, maximum} ->
      graph[resource]
      |> Enum.frequencies_by(&Map.fetch!(&1, parent))
      |> Enum.flat_map(fn {id, count} ->
        issue(count > maximum, id, "definition limit exceeded")
      end)
    end)
  end

  defp local_issues(graph, state) do
    Enum.flat_map(graph[QuestionDefinition], &question_issues(&1, graph, state == :published)) ++
      Enum.flat_map(graph[PresentationElement], fn element ->
        children =
          Enum.flat_map(Map.values(@presentations), fn resource ->
            Enum.filter(graph[resource], &(&1.element_id == element.id))
          end)

        issue(
          not match?([_], children) or
            not Enum.any?(children, &is_struct(&1, @presentations[element.kind])),
          element.id,
          "invalid presentation subtype"
        )
      end)
  end

  defp publication_issues(_graph, _version, :draft), do: []

  defp publication_issues(graph, version, :published) do
    issue(
      is_nil(version.title) or String.trim(version.title) == "",
      version.id,
      "title is required"
    ) ++
      issue(graph[InputSlotDefinition] == [], version.id, "input slot is required") ++
      issue(graph[QuestionDefinition] == [], version.id, "question is required") ++
      Enum.flat_map(graph[InputSlotDefinition], fn slot ->
        issue(
          not Enum.any?(graph[InputFieldRequirement], &(&1.input_slot_id == slot.id)),
          slot.id,
          "field requirement is required"
        )
      end) ++
      Enum.flat_map(graph[QuestionDefinition], fn question ->
        issue(
          Enum.count(graph[QuestionPlacement], &(&1.question_id == question.id)) != 1,
          question.id,
          "exactly one placement is required"
        )
      end)
  end

  defp question_issues(question, graph, published?) do
    typed =
      Enum.flat_map(
        @constraint_resources,
        &Enum.filter(graph[&1], fn row -> row.question_id == question.id end)
      )

    expected = @constraints[question.family]

    {own, incompatible?} =
      Enum.reduce(typed, {nil, false}, fn row, {matching, invalid?} ->
        if is_struct(row, expected), do: {row, invalid?}, else: {matching, true}
      end)

    source = Enum.find(graph[InputSource], &(&1.question_id == question.id))
    options = Enum.filter(graph[QuestionOption], &(&1.question_id == question.id))

    issue(
      question.renderer not in Map.fetch!(@renderers, question.family),
      question.id,
      "incompatible renderer"
    ) ++
      issue(
        incompatible?,
        question.id,
        "incompatible constraints"
      ) ++
      issue(
        published? and not is_nil(expected) and is_nil(own),
        question.id,
        "constraints are required"
      ) ++
      issue(
        options != [] and question.family not in @static,
        question.id,
        "static options are incompatible"
      ) ++
      issue(
        not is_nil(source) and question.family not in @dynamic,
        question.id,
        "input source is incompatible"
      ) ++
      scalar_issues(question, own, published?) ++
      choice_issues(question, own, source, options, graph, published?) ++
      annotation_issues(question, own, graph, published?)
  end

  defp scalar_issues(%{renderer: renderer} = question, %IntegerConstraints{} = bounds, published?)
       when renderer in [:stars, :likert] do
    missing = is_nil(bounds.minimum) or is_nil(bounds.maximum)

    issue(published? and missing, question.id, "explicit integer bounds are required") ++
      issue(
        not missing and bounds.maximum - bounds.minimum + 1 > 200,
        question.id,
        "integer range exceeds 200 values"
      )
  end

  defp scalar_issues(_question, _own, _published?), do: []

  defp choice_issues(question, bounds, source, options, graph, published?) do
    issues = single_choice_issues(question, bounds)

    cond do
      question.family in @static ->
        issues ++
          issue(
            published? and Enum.count_until(options, 2) < 2,
            question.id,
            "at least two options are required"
          ) ++
          issue(
            published? and not is_nil(bounds) and bounds.maximum > length(options),
            question.id,
            "selection exceeds available choices"
          )

      question.family in @dynamic ->
        issues ++ dynamic_issues(question, bounds, source, graph, published?)

      true ->
        issues
    end
  end

  defp single_choice_issues(%{family: family} = question, bounds)
       when family in @single and not is_nil(bounds) do
    issue(
      bounds.minimum != 1 or bounds.maximum != 1,
      question.id,
      "single choice requires one selection"
    )
  end

  defp single_choice_issues(_question, _bounds), do: []

  defp dynamic_issues(question, _bounds, nil, _graph, published?),
    do: issue(published?, question.id, "input source is required")

  defp dynamic_issues(question, bounds, source, graph, published?) do
    slot = Enum.find(graph[InputSlotDefinition], &(&1.id == source.input_slot_id))
    field = Enum.find(graph[InputFieldRequirement], &(&1.id == source.source_requirement_id))
    image? = question.renderer == :image_choice

    issue(is_nil(slot), question.id, "invalid input slot") ++
      issue(image? and not image_source?(field), question.id, "required image source is required") ++
      issue(not image? and not is_nil(field), question.id, "unexpected image source") ++
      issue(
        not is_nil(field) and field.input_slot_id != source.input_slot_id,
        question.id,
        "source belongs to another slot"
      ) ++
      slot_choice_issues(question, bounds, slot, published?)
  end

  defp slot_choice_issues(_question, _bounds, nil, _published?), do: []

  defp slot_choice_issues(question, bounds, slot, published?) do
    issue(
      published? and slot.minimum < 2,
      question.id,
      "at least two guaranteed input items are required"
    ) ++
      issue(
        published? and question.renderer == :pairwise and (slot.minimum != 2 or slot.maximum != 2),
        question.id,
        "pairwise requires exactly two items"
      ) ++
      issue(
        published? and not is_nil(bounds) and bounds.maximum > slot.minimum,
        question.id,
        "selection exceeds guaranteed items"
      )
  end

  defp annotation_issues(question, %AnnotationConstraints{} = bounds, graph, published?) do
    source = Enum.find(graph[InputFieldRequirement], &(&1.id == bounds.source_requirement_id))

    compatible? =
      if question.family == :text_spans,
        do: match?(%{required: true, value_family: :text, cardinality: :single}, source),
        else: image_source?(source)

    issue(not compatible?, question.id, "incompatible annotation source") ++
      issue(
        published? and not Enum.any?(graph[Label], &(&1.label_set_id == bounds.label_set_id)),
        question.id,
        "annotation labels are required"
      )
  end

  defp annotation_issues(_question, _own, _graph, _published?), do: []

  defp image_source?(source),
    do:
      match?(
        %{required: true, value_family: :asset, cardinality: :single, intended_use: :image},
        source
      )

  defp issue(true, id, message), do: [id <> ": " <> message]
  defp issue(false, _id, _message), do: []

  def copy!(source, destination) do
    graph = load!(source.id)
    ids = graph |> Map.values() |> List.flatten() |> Map.new(&{&1.id, Ash.UUID.generate()})

    Enum.each(@resources, fn resource ->
      attributes = Enum.map(graph[resource], &copy_attributes(resource, &1, destination.id, ids))

      Ash.bulk_create!(attributes, resource, :create_internal,
        authorize?: false,
        transaction: :all,
        stop_on_error?: true
      )
    end)

    validate!(destination, :draft)
  end

  defp copy_attributes(resource, original, destination_id, ids) do
    names = ResourceInfo.action(resource, :create_internal).accept

    references =
      resource |> ResourceInfo.relationships() |> Enum.filter(&(&1.type == :belongs_to))

    attributes = Map.take(original, names)

    Enum.reduce(references, attributes, fn relationship, attributes ->
      Map.update!(attributes, relationship.source_attribute, fn
        nil -> nil
        _old when relationship.source_attribute == :version_id -> destination_id
        old -> Map.fetch!(ids, old)
      end)
    end)
    |> Map.put(:copied_id, Map.fetch!(ids, original.id))
  end
end
