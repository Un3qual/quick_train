defmodule QuickTrain.Tasks.AnswerValidation do
  @moduledoc "Validates normalized outcomes after the caller locks and authorizes their attempt."

  alias QuickTrain.Datasets.{DatasetItemRevision, DatasetValue}
  alias QuickTrain.Forms.Inputs.InputFieldRequirement
  alias QuickTrain.Forms.Labels.Label
  alias QuickTrain.Forms.Questions.QuestionOption

  alias QuickTrain.Forms.Questions.Constraints.{
    AnnotationConstraints,
    DecimalConstraints,
    IntegerConstraints,
    SelectionConstraints,
    TextConstraints
  }

  alias QuickTrain.Projects.ProjectInputBinding
  alias QuickTrain.Tasks.{Error, TaskInput}
  alias QuickTrain.Tasks.Inputs.AnswerInput
  require Ash.Query

  @scalars [:text_value, :integer_value, :decimal_value, :boolean_value]
  @collections [:option_ids, :inputs, :spans]
  @scalar_types %{
    text: {:text_value, :string, TextConstraints},
    integer: {:integer_value, :integer, IntegerConstraints},
    decimal: {:decimal_value, :decimal, DecimalConstraints},
    boolean: {:boolean_value, :boolean, nil}
  }

  def validate!(project, task, question, input, stage) when stage in [:draft, :submit] do
    require!(
      task.project_id == project.id and task.organization_id == project.organization_id and
        task.form_version_id == project.form_version_id and
        question.version_id == project.form_version_id
    )

    answer = cast_answer!(input)
    require!(answer.family == question.family)

    require!(
      answer.family in (Map.keys(@scalar_types) ++
                          [
                            :static_single_choice,
                            :static_multiple_choice,
                            :task_input_single_choice,
                            :task_input_multiple_choice,
                            :task_input_ranking,
                            :text_spans
                          ])
    )

    optional_text!(answer.reason)
    optional_text!(answer.explanation)

    attributes =
      Map.take(answer, [:outcome, :family, :reason, :explanation | @scalars])
      |> Map.put(:skipped_at, nil)

    result = %{attributes: attributes, option_ids: [], inputs: [], spans: []}

    case answer.outcome do
      :skipped ->
        only_payload!(answer, [])
        require!(is_nil(answer.reason) or String.trim(answer.reason) != "")
        put_in(result.attributes.skipped_at, DateTime.utc_now())

      :answered ->
        require!(is_nil(answer.reason) and is_nil(answer.explanation))
        validate_answer!(result, project, task, question, answer, stage)
    end
  end

  defp validate_answer!(result, _project, _task, question, answer, stage)
       when is_map_key(@scalar_types, question.family) do
    {field, type, constraint_resource} = Map.fetch!(@scalar_types, question.family)
    only_payload!(answer, [field])
    value = Map.fetch!(answer, field)
    require!(stage == :draft or not is_nil(value))

    if is_nil(value) do
      result
    else
      if type == :string, do: optional_text!(value)
      bounds = if constraint_resource, do: constraint!(constraint_resource, question), else: nil
      constraints = scalar_constraints(type, bounds)

      with {:ok, value} <- Ash.Type.cast_input(type, value, constraints),
           {:ok, value} <- Ash.Type.apply_constraints(type, value, constraints) do
        put_in(result.attributes[field], value)
      else
        _invalid -> Error.reject!(:invalid_answer)
      end
    end
  end

  defp validate_answer!(result, _project, _task, question, answer, stage)
       when question.family in [:static_single_choice, :static_multiple_choice] do
    only_payload!(answer, [:option_ids])
    unique!(answer.option_ids)
    count!(length(answer.option_ids), selection_bounds(question), stage)

    selected =
      Ash.count!(QuestionOption,
        query: [
          filter: [
            id: [in: answer.option_ids],
            question_id: question.id,
            version_id: question.version_id
          ]
        ],
        authorize?: false
      )

    require!(selected == length(answer.option_ids))
    %{result | option_ids: answer.option_ids}
  end

  defp validate_answer!(result, project, task, question, answer, stage)
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

  defp validate_answer!(result, project, task, question, answer, stage)
       when question.family == :text_spans do
    only_payload!(answer, [:spans])

    spans =
      Enum.map(
        answer.spans,
        &Map.take(&1, [:task_input_id, :source_value_id, :label_id, :start, :end])
      )

    unique!(spans)
    bounds = constraint!(AnnotationConstraints, question)
    require!(not is_nil(bounds))
    count!(length(spans), bounds, stage)

    requirement =
      InputFieldRequirement
      |> Ash.Query.filter(
        id == ^bounds.source_requirement_id and version_id == ^question.version_id and
          value_family == :text and required == true and cardinality == :single
      )
      |> Ash.read_one!(authorize?: false)

    require!(not is_nil(requirement))
    inputs = slot_inputs!(project, task, requirement.input_slot_id)
    allowed_ids = MapSet.new(inputs, & &1.id)
    require!(Enum.all?(spans, &MapSet.member?(allowed_ids, &1.task_input_id)))
    labels = spans |> Enum.map(& &1.label_id) |> Enum.uniq()

    count =
      Ash.count!(Label,
        query: [
          filter: [
            id: [in: labels],
            label_set_id: bounds.label_set_id,
            version_id: question.version_id
          ]
        ],
        authorize?: false
      )

    require!(count == length(labels))
    validate_sources!(project, requirement, inputs, spans)
    %{result | spans: spans}
  end

  defp validate_sources!(_project, _requirement, _inputs, []), do: :ok

  defp validate_sources!(project, requirement, inputs, spans) do
    binding =
      ProjectInputBinding
      |> Ash.Query.filter(
        project_id == ^project.id and form_version_id == ^project.form_version_id and
          requirement_id == ^requirement.id
      )
      |> Ash.read_one!(authorize?: false)

    require!(not is_nil(binding))
    selected_inputs = MapSet.new(spans, & &1.task_input_id)
    inputs = Enum.filter(inputs, &MapSet.member?(selected_inputs, &1.id))

    revisions =
      DatasetItemRevision
      |> Ash.Query.filter(
        id in ^Enum.map(inputs, & &1.revision_id) and organization_id == ^project.organization_id and
          dataset_id == ^project.dataset_id and schema_version_id == ^project.schema_version_id
      )
      |> Ash.read!(authorize?: false, page: false)

    roots = Map.new(revisions, &{&1.id, &1.root_record_id})

    sources =
      DatasetValue
      |> Ash.Query.filter(
        id in ^Enum.map(spans, & &1.source_value_id) and
          organization_id == ^project.organization_id and
          field_definition_id == ^binding.field_definition_id and record_id in ^Map.values(roots)
      )
      |> Ash.Query.load(:text_value)
      |> Ash.read!(authorize?: false, page: false)
      |> Map.new(fn source ->
        require!(not is_nil(source.text_value))
        text = source.text_value.value
        optional_text!(text)
        {source.id, %{record_id: source.record_id, length: length(String.codepoints(text))}}
      end)

    input_roots = Map.new(inputs, &{&1.id, Map.get(roots, &1.revision_id)})

    Enum.each(spans, &validate_span_source!(&1, sources, input_roots))
  end

  defp validate_span_source!(span, sources, input_roots) do
    source = Map.get(sources, span.source_value_id)

    require!(not is_nil(source) and source.record_id == Map.get(input_roots, span.task_input_id))

    require!(
      is_integer(span.start) and is_integer(span.end) and span.start >= 0 and
        span.start < span.end and span.end <= source.length
    )
  end

  defp slot_inputs!(project, task, slot_id) do
    TaskInput
    |> Ash.Query.filter(
      organization_id == ^project.organization_id and project_id == ^project.id and
        form_version_id == ^project.form_version_id and task_id == ^task.id and
        input_slot_id == ^slot_id
    )
    |> Ash.Query.select([:id, :revision_id])
    |> Ash.read!(authorize?: false, page: false)
  end

  defp constraint!(resource, question),
    do:
      resource
      |> Ash.Query.filter(question_id == ^question.id and version_id == ^question.version_id)
      |> Ash.read_one!(authorize?: false)

  defp selection_bounds(%{family: family})
       when family in [:static_single_choice, :task_input_single_choice],
       do: %{minimum: 1, maximum: 1}

  defp selection_bounds(question) do
    bounds = constraint!(SelectionConstraints, question)
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

  defp cast_answer!(input) do
    case Ash.Type.cast_input(AnswerInput, input) do
      {:ok, %AnswerInput{} = answer} -> answer
      _invalid -> Error.reject!(:invalid_answer)
    end
  end
end
