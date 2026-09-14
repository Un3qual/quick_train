defmodule QuickTrain.Tasks.Exports.Jsonl do
  alias QuickTrain.Projects.Project
  alias QuickTrain.Tasks.Error
  alias QuickTrain.Tasks.Exports.{ExportSelection, Snapshot}
  @moduledoc false
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
      project = Ash.get!(Project, export.project_id, authorize?: false)

      header = %{
        kind: :header,
        format_version: 1,
        record_count: Integer.to_string(export.record_count),
        snapshot_at: export.snapshot_at,
        organization_id: export.organization_id,
        project_id: export.project_id,
        form_version_id: export.form_version_id,
        schema_version_id: project.schema_version_id,
        mode: export.mode,
        task_id_from: export.task_id_from,
        task_id_to: export.task_id_to,
        evidence_kind: export.evidence_kind,
        evidence_id_from: export.evidence_id_from,
        evidence_id_to: export.evidence_id_to
      }

      initial = write_line!(file, header, {:crypto.hash_init(:sha256), 0, 0})

      {hash, size, count} =
        Snapshot.kinds()
        |> Enum.sort()
        |> Enum.reduce(initial, &write_kind!(file, export, project.schema_version_id, &1, &2))

      if count != export.record_count,
        do: Error.reject!(:export_snapshot_mismatch)

      %{sha256: :crypto.hash_final(hash), byte_size: size, media_type: "application/x-ndjson"}
    end)
  end

  defp write_kind!(file, export, schema_version_id, kind, state) do
    Snapshot.rows(export, kind, loads(kind))
    |> Stream.chunk_every(100)
    |> Enum.reduce(state, fn rows, state ->
      selections = selections(export, kind, rows)

      Enum.reduce(rows, state, fn row, {hash, size, count} ->
        value =
          row(selections, kind, row)
          |> Map.merge(%{
            kind: kind,
            organization_id: export.organization_id,
            project_id: export.project_id,
            form_version_id: export.form_version_id,
            schema_version_id: schema_version_id
          })

        write_line!(file, value, {hash, size, count + 1})
      end)
    end)
  end

  defp selections(export, kind, rows)
       when kind in [
              :question_response,
              :static_option_answer,
              :task_input_answer,
              :text_span,
              :dataset_value
            ] do
    field = if kind == :dataset_value, do: :dataset_value_id, else: :question_response_id

    row_field =
      if kind in [:question_response, :dataset_value], do: :id, else: :question_response_id

    ids = Enum.map(rows, &Map.fetch!(&1, row_field)) |> Enum.uniq()

    ExportSelection
    |> Ash.Query.filter(export_id == ^export.id and kind == ^kind)
    |> Ash.Query.filter(^[{field, [in: ids]}])
    |> Ash.read!(authorize?: false, page: false)
    |> Map.new(&{Map.fetch!(&1, field), &1})
  end

  defp selections(_export, _kind, _rows), do: %{}

  defp loads(:question_response), do: [:response]

  defp loads(kind) when kind in [:static_option_answer, :task_input_answer, :text_span],
    do: [question_response: :response]

  defp loads(:question_definition),
    do:
      [annotation_constraints: :source_convention] ++ (@constraints -- [:annotation_constraints])

  defp loads(:project_input_binding), do: [:requirement, :field_definition]

  defp loads(:dataset_value),
    do: [:field_definition, asset_value: :asset] ++ (@typed_values -- [:asset_value])

  defp loads(_kind), do: []

  defp write_line!(file, value, {hash, size, count}) do
    bytes = [Jason.encode_to_iodata!(value), "\n"]
    :ok = IO.binwrite(file, bytes)
    {:crypto.hash_update(hash, bytes), size + IO.iodata_length(bytes), count}
  end

  defp row(_selections, :task, row), do: row |> fields() |> Map.drop([:state, :updated_at])

  defp row(selections, :question_response, row) do
    selection = Map.fetch!(selections, row.id)

    row
    |> fields()
    |> Map.merge(%{
      effective_decision_id: selection.decision_id,
      attempt_id: row.response.attempt_id,
      submitted_at: row.response.submitted_at
    })
  end

  defp row(_selections, :presentation_element, row),
    do: Map.put(fields(row), :element_kind, row.kind)

  defp row(selections, kind, row)
       when kind in [:static_option_answer, :task_input_answer, :text_span] do
    selection = Map.fetch!(selections, row.question_response_id)

    response = row.question_response.response

    fields(row)
    |> Map.merge(%{
      response_id: response.id,
      attempt_id: response.attempt_id,
      effective_decision_id: selection.decision_id
    })
  end

  defp row(_selections, :question_definition, row) do
    Enum.reduce(@constraints, fields(row), fn key, value ->
      constraint = Map.fetch!(row, key)

      serialized = if constraint, do: fields(constraint), else: nil

      serialized =
        if key == :annotation_constraints and constraint,
          do: Map.put(serialized, :source_convention, constraint.source_convention),
          else: serialized

      Map.put(value, key, serialized)
    end)
  end

  defp row(_selections, :project_input_binding, row) do
    fields(row)
    |> Map.merge(%{
      input_slot_id: row.requirement.input_slot_id,
      requirement_key: row.requirement.key,
      requirement_family: row.requirement.value_family,
      requirement_intended_use: row.requirement.intended_use,
      field_key: row.field_definition.key
    })
  end

  defp row(selections, :dataset_value, row) do
    selected = Map.fetch!(selections, row.id)

    value =
      Enum.reduce(@typed_values, fields(row), fn key, result ->
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

        Map.put(result, key, content)
      end)

    Map.merge(value, %{
      revision_id: selected.revision_id,
      field_definition_id: selected.field_definition_id,
      field_key: row.field_definition.key,
      family: row.field_definition.value_family
    })
  end

  defp row(_selections, _kind, row), do: fields(row)

  defp fields(%resource{} = row) do
    resource
    |> Ash.Resource.Info.public_attributes()
    |> Enum.map(& &1.name)
    |> then(&Map.take(row, &1))
    |> Map.drop([:updated_at, :request_key])
    |> Map.new(fn {key, value} -> {key, exact(value)} end)
  end

  defp exact(%Decimal{} = value), do: Decimal.to_string(value, :normal)
  defp exact(value), do: value
end
