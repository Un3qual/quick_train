defmodule QuickTrain.Tasks.Responses.AnswerValidation do
  @moduledoc "Validates normalized outcomes after the caller locks and authorizes their attempt."

  alias QuickTrain.Datasets.{DatasetItemRevision, DatasetValue}
  alias QuickTrain.Tasks.Error
  alias QuickTrain.Tasks.Responses.Inputs.AnswerInput
  require Ash.Query

  @scalars [:text_value, :integer_value, :decimal_value, :boolean_value]
  @collections [:option_ids, :inputs, :spans]
  @scalar_types %{
    text: {:text_value, :string, :text_constraints},
    integer: {:integer_value, :integer, :integer_constraints},
    decimal: {:decimal_value, :decimal, :decimal_constraints},
    boolean: {:boolean_value, :boolean, nil}
  }

  def skip_policies!(project, outcomes) do
    skipped = Enum.filter(outcomes, &(&1.outcome == :skipped))

    Enum.each(skipped, fn attrs ->
      unless project.skip_allowed, do: Error.reject!(:skip_not_allowed)

      if project.reason_required and (is_nil(attrs.reason) or String.trim(attrs.reason) == ""),
        do: Error.reject!(:skip_reason_required)
    end)
  end

  def stored_answer(outcome) do
    attrs =
      Map.take(outcome, [
        :outcome,
        :family,
        :reason,
        :explanation,
        :text_value,
        :integer_value,
        :decimal_value,
        :boolean_value
      ])

    options =
      outcome.static_options
      |> Enum.map(& &1.option_id)

    inputs =
      outcome.input_answers
      |> Enum.map(&Map.take(&1, [:task_input_id, :position]))

    spans =
      outcome.text_spans
      |> Enum.map(&Map.take(&1, [:task_input_id, :source_value_id, :label_id, :start, :end]))

    Map.merge(attrs, %{option_ids: options, inputs: inputs, spans: spans})
  end

  def validate!(project, task, question, input, stage, span_sources \\ nil)
      when stage in [:draft, :submit] do
    require!(
      task.project_id == project.id and task.organization_id == project.organization_id and
        task.form_version_id == project.form_version_id and
        question.version_id == project.form_version_id
    )

    answer = cast_answer!(input)
    require!(answer.family == question.family)

    optional_text!(answer.reason)
    optional_text!(answer.explanation)

    attributes =
      Map.take(answer, [:outcome, :family, :reason, :explanation | @scalars])
      |> Map.put(:skipped_at, nil)

    result = %{attributes: attributes, option_ids: [], inputs: [], spans: []}

    case answer.outcome do
      :skipped ->
        only_payload!(answer, [])
        put_in(result.attributes.skipped_at, DateTime.utc_now())

      :answered ->
        question =
          Ash.load!(question, question_load(question.family), authorize?: false, lazy?: true)

        validate_answer!(result, project, task, question, answer, stage, span_sources)
    end
  end

  def load_questions!(questions) do
    questions
    |> Enum.group_by(& &1.family)
    |> Enum.flat_map(fn {family, questions} ->
      Ash.load!(questions, question_load(family), authorize?: false, lazy?: true)
    end)
  end

  defp question_load(:text), do: [:text_constraints]
  defp question_load(:integer), do: [:integer_constraints]
  defp question_load(:decimal), do: [:decimal_constraints]
  defp question_load(:static_single_choice), do: [:options]
  defp question_load(:static_multiple_choice), do: [:selection_constraints, :options]
  defp question_load(:task_input_multiple_choice), do: [:selection_constraints]

  defp question_load(:text_spans),
    do: [annotation_constraints: [:source_requirement, label_set: :labels]]

  defp question_load(_family), do: []

  defp validate_answer!(result, _project, _task, question, answer, stage, _span_sources)
       when is_map_key(@scalar_types, question.family) do
    {field, type, constraint_relationship} = Map.fetch!(@scalar_types, question.family)
    only_payload!(answer, [field])
    value = Map.fetch!(answer, field)
    require!(stage == :draft or not is_nil(value))

    if is_nil(value) do
      result
    else
      if type == :string, do: optional_text!(value)
      bounds = if constraint_relationship, do: Map.fetch!(question, constraint_relationship)
      constraints = scalar_constraints(type, bounds)

      with {:ok, value} <- Ash.Type.cast_input(type, value, constraints),
           {:ok, value} <- Ash.Type.apply_constraints(type, value, constraints) do
        put_in(result.attributes[field], value)
      else
        _invalid -> Error.reject!(:invalid_answer)
      end
    end
  end

  defp validate_answer!(result, _project, _task, question, answer, stage, _span_sources)
       when question.family in [:static_single_choice, :static_multiple_choice] do
    only_payload!(answer, [:option_ids])
    unique!(answer.option_ids)
    count!(length(answer.option_ids), selection_bounds(question), stage)

    allowed = MapSet.new(question.options, & &1.id)

    require!(MapSet.subset?(MapSet.new(answer.option_ids), allowed))
    %{result | option_ids: answer.option_ids}
  end

  defp validate_answer!(result, project, task, question, answer, stage, _span_sources)
       when question.family in [
              :task_input_single_choice,
              :task_input_multiple_choice,
              :task_input_ranking
            ] do
    only_payload!(answer, [:inputs])
    inputs = Enum.map(answer.inputs, &Map.take(&1, [:task_input_id, :position]))
    ids = Enum.map(inputs, & &1.task_input_id)
    unique!(ids)
    allowed = slot_inputs!(project, task, question.input_slot_id)
    allowed_ids = MapSet.new(allowed, & &1.id)
    require!(Enum.all?(ids, &MapSet.member?(allowed_ids, &1)))

    if question.family == :task_input_ranking do
      total = length(allowed)
      count!(length(inputs), %{minimum: total, maximum: total}, stage)
      positions = Enum.map(inputs, & &1.position)
      unique!(positions)
      require!(Enum.all?(positions, &(is_integer(&1) and &1 >= 0 and &1 < total)))
    else
      count!(length(inputs), selection_bounds(question), stage)
      require!(Enum.all?(inputs, &is_nil(&1.position)))
    end

    %{result | inputs: inputs}
  end

  defp validate_answer!(result, project, task, question, answer, stage, span_sources)
       when question.family == :text_spans do
    only_payload!(answer, [:spans])

    spans =
      Enum.map(
        answer.spans,
        &Map.take(&1, [:task_input_id, :source_value_id, :label_id, :start, :end])
      )

    unique!(spans)
    bounds = question.annotation_constraints
    require!(not is_nil(bounds))
    count!(length(spans), bounds, stage)

    requirement = bounds.source_requirement

    require!(
      requirement && requirement.version_id == question.version_id &&
        requirement.value_family == :text && requirement.required &&
        requirement.cardinality == :single
    )

    inputs = slot_inputs!(project, task, requirement.input_slot_id)
    allowed_ids = MapSet.new(inputs, & &1.id)
    require!(Enum.all?(spans, &MapSet.member?(allowed_ids, &1.task_input_id)))
    labels = spans |> Enum.map(& &1.label_id) |> Enum.uniq()

    allowed_labels = MapSet.new(bounds.label_set.labels, & &1.id)

    require!(MapSet.subset?(MapSet.new(labels), allowed_labels))
    validate_sources!(project, requirement, inputs, spans, span_sources)
    %{result | spans: spans}
  end

  defp validate_sources!(_project, _requirement, _inputs, [], _span_sources), do: :ok

  defp validate_sources!(project, requirement, inputs, spans, span_sources) do
    binding =
      project
      |> Ash.load!(:bindings, authorize?: false, lazy?: true)
      |> Map.fetch!(:bindings)
      |> Enum.find(&(&1.requirement_id == requirement.id))

    require!(not is_nil(binding))

    %{sources: sources, input_roots: input_roots} =
      span_sources || load_span_sources!(project, inputs, spans)

    Enum.each(
      spans,
      &validate_span_source!(&1, sources, input_roots, binding.field_definition_id)
    )
  end

  def load_span_sources!(_project, _inputs, []), do: %{sources: %{}, input_roots: %{}}

  def load_span_sources!(project, inputs, spans) do
    selected_inputs = MapSet.new(spans, & &1.task_input_id)
    inputs = Enum.filter(inputs, &MapSet.member?(selected_inputs, &1.id))
    source_ids = spans |> Enum.map(& &1.source_value_id) |> Enum.uniq()
    revision_ids = inputs |> Enum.map(& &1.revision_id) |> Enum.uniq()

    values =
      DatasetValue
      |> Ash.Query.filter(id in ^source_ids and organization_id == ^project.organization_id)
      |> Ash.Query.load(:text_value)

    revisions =
      DatasetItemRevision
      |> Ash.Query.filter(
        id in ^revision_ids and organization_id == ^project.organization_id and
          dataset_id == ^project.dataset_id and schema_version_id == ^project.schema_version_id
      )
      |> Ash.Query.load(root_record: [values: values])
      |> Ash.read!(authorize?: false, page: false)

    roots = Map.new(revisions, &{&1.id, &1.root_record_id})

    sources =
      revisions
      |> Enum.flat_map(& &1.root_record.values)
      |> Enum.uniq_by(& &1.id)
      |> Map.new(fn source ->
        require!(not is_nil(source.text_value))
        text = source.text_value.value
        optional_text!(text)

        {source.id,
         %{
           record_id: source.record_id,
           field_definition_id: source.field_definition_id,
           length: length(String.codepoints(text))
         }}
      end)

    input_roots = Map.new(inputs, &{&1.id, Map.get(roots, &1.revision_id)})

    %{sources: sources, input_roots: input_roots}
  end

  defp validate_span_source!(span, sources, input_roots, field_id) do
    source = Map.get(sources, span.source_value_id)

    require!(
      not is_nil(source) and source.field_definition_id == field_id and
        source.record_id == Map.get(input_roots, span.task_input_id)
    )

    require!(span.end <= source.length)
  end

  defp slot_inputs!(project, task, slot_id) do
    task
    |> Ash.load!(:inputs, authorize?: false, lazy?: true)
    |> Map.fetch!(:inputs)
    |> Enum.filter(
      &(&1.organization_id == project.organization_id and &1.project_id == project.id and
          &1.form_version_id == project.form_version_id and &1.input_slot_id == slot_id)
    )
  end

  defp selection_bounds(%{family: family})
       when family in [:static_single_choice, :task_input_single_choice],
       do: %{minimum: 1, maximum: 1}

  defp selection_bounds(question) do
    bounds = question.selection_constraints
    require!(not is_nil(bounds))
    bounds
  end

  defp scalar_constraints(:string, bounds),
    do:
      [trim?: false, allow_empty?: true, length_count: :codepoints] ++
        bounds_keywords(bounds, :min_length, :max_length)

  defp scalar_constraints(:integer, bounds),
    do: [
      min: if(bounds && bounds.minimum, do: bounds.minimum, else: -2_147_483_648),
      max: if(bounds && bounds.maximum, do: bounds.maximum, else: 2_147_483_647)
    ]

  defp scalar_constraints(:decimal, bounds), do: bounds_keywords(bounds, :min, :max)
  defp scalar_constraints(:boolean, _bounds), do: []
  defp bounds_keywords(nil, _min, _max), do: []

  defp bounds_keywords(bounds, min, max),
    do:
      [{min, bounds.minimum}, {max, bounds.maximum}]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

  defp count!(count, bounds, stage),
    do: require!(count <= bounds.maximum and (stage == :draft or count >= bounds.minimum))

  defp unique!(values), do: require!(length(values) == length(Enum.uniq(values)))

  defp only_payload!(answer, allowed) do
    require!(Enum.all?(@scalars -- allowed, &is_nil(Map.fetch!(answer, &1))))
    require!(Enum.all?(@collections -- allowed, &(Map.fetch!(answer, &1) == [])))
  end

  defp optional_text!(nil), do: :ok

  defp optional_text!(text),
    do: require!(is_binary(text) and String.valid?(text) and not String.contains?(text, <<0>>))

  defp require!(true), do: :ok
  defp require!(_invalid), do: Error.reject!(:invalid_answer)

  defp cast_answer!(%AnswerInput{} = input) do
    fields = AnswerInput |> Ash.Resource.Info.attribute_names() |> Enum.to_list()
    input |> Map.take(fields) |> cast_answer!()
  end

  defp cast_answer!(input) do
    case Ash.Type.cast_input(AnswerInput, input) do
      {:ok, %AnswerInput{} = answer} -> answer
      _invalid -> Error.reject!(:invalid_answer)
    end
  end
end
