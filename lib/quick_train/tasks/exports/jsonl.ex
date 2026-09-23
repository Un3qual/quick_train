defmodule QuickTrain.Tasks.Exports.Jsonl do
  @moduledoc false
  alias QuickTrain.Datasets.DatasetValue
  alias QuickTrain.Forms.Labels.Label
  alias QuickTrain.Forms.Presentation.PresentationElement
  alias QuickTrain.Forms.Questions.Constraints.AnnotationConstraints
  alias QuickTrain.Forms.Questions.{QuestionDefinition, QuestionOption}
  alias QuickTrain.Projects.{Project, ProjectInputBinding}
  alias QuickTrain.Tasks.Attempts.AttemptInputPresentation
  alias QuickTrain.Tasks.Error
  alias QuickTrain.Tasks.Exports.Snapshot
  alias QuickTrain.Tasks.Responses.{StaticOptionAnswer, TaskInputAnswer, TextSpan}
  alias QuickTrain.Tasks.Reviews.ReviewDecision
  require Ash.Query

  @constraints [
    :text_constraints,
    :integer_constraints,
    :decimal_constraints,
    :selection_constraints,
    :annotation_constraints
  ]
  @typed_values [
    :text_value,
    :integer_value,
    :decimal_value,
    :boolean_value,
    :date_time_value,
    :asset_value
  ]

  def write!(export, path) do
    File.open!(path, [:write, :binary, :exclusive], fn file ->
      initial = write_line!(file, header(export), {:crypto.hash_init(:sha256), 0})

      {{hash, size}, count} =
        Snapshot.rows(export)
        |> Enum.reduce({initial, 0}, fn selection, {state, count} ->
          {write_line!(file, result(export, selection), state), count + 1}
        end)

      if count != export.record_count, do: Error.reject!(:export_snapshot_mismatch)
      %{sha256: :crypto.hash_final(hash), byte_size: size, media_type: "application/x-ndjson"}
    end)
  end

  defp header(export) do
    project = Ash.get!(Project, export.project_id, authorize?: false)

    fields = %{
      kind: :header,
      format_version: 1,
      record_count: Integer.to_string(export.record_count),
      snapshot_at: export.snapshot_at,
      organization_id: export.organization_id,
      project_id: export.project_id,
      form_version_id: export.form_version_id,
      schema_version_id: project.schema_version_id,
      mode: export.mode
    }

    if export.record_count == 0 do
      object(fields)
    else
      questions =
        QuestionDefinition
        |> Ash.Query.filter(version_id == ^export.form_version_id)
        |> Ash.Query.load(
          [annotation_constraints: :source_convention] ++
            (@constraints -- [:annotation_constraints])
        )
        |> stream()
        |> Stream.map(&question/1)

      labels =
        Label
        |> Ash.Query.filter(
          version_id == ^export.form_version_id and
            exists(
              AnnotationConstraints,
              version_id == ^export.form_version_id and label_set_id == parent(label_set_id)
            )
        )

      bindings =
        ProjectInputBinding
        |> Ash.Query.filter(project_id == ^export.project_id)
        |> Ash.Query.load([:requirement, :field_definition])
        |> stream()
        |> Stream.map(fn binding ->
          object(
            Map.merge(fields(binding), %{
              requirement: fields(binding.requirement),
              field: fields(binding.field_definition)
            })
          )
        end)

      presentation = Ash.Query.filter(PresentationElement, version_id == ^export.form_version_id)

      object(fields,
        presentation: objects(presentation),
        questions: questions,
        labels: objects(labels),
        bindings: bindings
      )
    end
  end

  defp question(question) do
    fields =
      Enum.reduce(@constraints, fields(question), fn key, fields ->
        constraint = Map.fetch!(question, key)
        value = if constraint, do: fields(constraint)

        value =
          if key == :annotation_constraints and constraint,
            do: Map.put(value, :source_convention, constraint.source_convention),
            else: value

        Map.put(fields, key, value)
      end)

    options = Ash.Query.filter(QuestionOption, question_id == ^question.id)
    object(fields, options: objects(options))
  end

  defp result(export, selection) do
    response = selection.question_response

    fields =
      fields(response)
      |> Map.merge(%{
        kind: :result,
        effective_decision_id: selection.decision_id,
        submitted_at: response.attempt.terminal_at,
        attempt: fields(response.attempt) |> Map.drop([:revision]),
        task: fields(response.task)
      })

    inputs =
      AttemptInputPresentation
      |> Ash.Query.filter(attempt_id == ^response.attempt_id)
      |> Ash.Query.sort(input_slot_id: :asc, position: :asc, id: :asc)
      |> Ash.stream!(batch_size: 100, authorize?: false)
      |> Stream.chunk_every(100)
      |> Stream.flat_map(&inputs(export, &1))

    decisions =
      ReviewDecision
      |> Ash.Query.filter(question_response_id == ^response.id)
      |> Ash.Query.sort(number: :asc, id: :asc)
      |> then(fn query ->
        cond do
          is_nil(selection.decision_id) -> Ash.Query.filter(query, false)
          export.mode == :accepted -> Ash.Query.filter(query, id == ^selection.decision_id)
          true -> Ash.Query.filter(query, number <= ^selection.decision.number)
        end
      end)
      |> Ash.stream!(batch_size: 100, authorize?: false)
      |> Stream.map(&object(fields(&1)))

    object(fields,
      inputs: inputs,
      static_options: answers(StaticOptionAnswer, response),
      input_answers: answers(TaskInputAnswer, response),
      text_spans: answers(TextSpan, response),
      review_decisions: decisions
    )
  end

  defp inputs(export, presentations) do
    presentations
    |> Enum.chunk_by(& &1.input_slot_id)
    |> Enum.flat_map(fn [first | _] = presentations ->
      slot_id = first.input_slot_id

      values =
        DatasetValue
        |> Ash.Query.filter(
          exists(
            ProjectInputBinding,
            project_id == ^export.project_id and
              field_definition_id == parent(field_definition_id) and
              requirement.input_slot_id == ^slot_id
          )
        )
        |> Ash.Query.sort(id: :asc)
        |> Ash.Query.load(
          [:field_definition, asset_value: :asset] ++ (@typed_values -- [:asset_value])
        )

      # A published slot has at most 64 single-value requirements.
      Ash.load!(presentations, [task_input: [revision: [root_record: [values: values]]]],
        authorize?: false
      )
    end)
    |> Enum.map(&input/1)
  end

  defp input(presentation) do
    input = presentation.task_input

    values =
      input.revision.root_record.values
      |> Stream.map(&object(value(&1)))

    object(Map.merge(fields(input), %{position: presentation.position}), values: values)
  end

  defp value(row) do
    Enum.reduce(@typed_values, fields(row), fn key, fields ->
      child = Map.fetch!(row, key)

      content =
        cond do
          is_nil(child) ->
            nil

          key == :asset_value ->
            asset = child.asset

            %{
              id: asset.id,
              sha256: Base.encode16(asset.sha256, case: :lower),
              byte_size: asset.byte_size,
              media_type: asset.media_type,
              width: asset.width,
              height: asset.height
            }

          true ->
            exact(child.value)
        end

      Map.put(fields, key, content)
    end)
    |> Map.merge(%{
      field_key: row.field_definition.key,
      family: row.field_definition.value_family
    })
  end

  defp answers(resource, response),
    do: resource |> Ash.Query.filter(question_response_id == ^response.id) |> objects()

  defp stream(query), do: Ash.stream!(query, batch_size: 100, authorize?: false)

  defp objects(query), do: query |> stream() |> Stream.map(&object(fields(&1)))

  # Only collections stream through this writer. Jason encodes every key and
  # value; nested arrays are emitted page by page without buffering a result.
  defp object(fields, arrays \\ []) do
    entries =
      fields
      |> Enum.sort_by(fn {key, _} -> to_string(key) end)
      |> Enum.map(fn {key, value} -> [[encode(key), ":", encode(value)]] end)

    arrays =
      Enum.map(arrays, fn {key, objects} ->
        Stream.concat([
          [[encode(key), ":["]],
          objects |> Stream.intersperse([","]) |> Stream.flat_map(& &1),
          ["]"]
        ])
      end)

    Stream.concat([
      ["{"],
      Stream.concat(entries, arrays) |> Stream.intersperse([","]) |> Stream.flat_map(& &1),
      ["}"]
    ])
  end

  defp write_line!(file, chunks, state) do
    max_bytes = Application.fetch_env!(:quick_train, :assets) |> Keyword.fetch!(:max_bytes)

    Stream.concat(chunks, ["\n"])
    |> Enum.reduce(state, fn bytes, {hash, size} ->
      size = size + IO.iodata_length(bytes)
      if size > max_bytes, do: Error.reject!(:byte_cap_exceeded)
      :ok = IO.binwrite(file, bytes)
      {:crypto.hash_update(hash, bytes), size}
    end)
  end

  defp fields(%resource{} = row) do
    resource
    |> Ash.Resource.Info.public_attributes()
    |> Enum.map(& &1.name)
    |> then(&Map.take(row, &1))
    |> Map.drop([:updated_at, :request_key])
    |> Map.new(fn {key, value} -> {key, exact(value)} end)
  end

  defp encode(value), do: Jason.encode_to_iodata!(ordered(value))
  defp ordered(%_{} = value), do: value

  defp ordered(value) when is_map(value) do
    value
    |> Enum.map(fn {key, child} -> {to_string(key), ordered(child)} end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Jason.OrderedObject.new()
  end

  defp ordered(value), do: value
  defp exact(%Decimal{} = value), do: Decimal.to_string(value, :normal)
  defp exact(value), do: value
end
