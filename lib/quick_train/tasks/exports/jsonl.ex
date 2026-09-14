defmodule QuickTrain.Tasks.Exports.Jsonl do
  alias QuickTrain.Assets.Asset
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
    |> Enum.reduce(state, fn row, {hash, size, count} ->
      value =
        row(export, kind, row)
        |> Map.merge(%{
          kind: kind,
          organization_id: export.organization_id,
          project_id: export.project_id,
          form_version_id: export.form_version_id,
          schema_version_id: schema_version_id
        })

      write_line!(file, value, {hash, size, count + 1})
    end)
  end

  defp loads(:question_response), do: [:response]

  defp loads(kind) when kind in [:static_option_answer, :task_input_answer, :text_span],
    do: [question_response: :response]

  defp loads(:question_definition),
    do:
      [annotation_constraints: :source_convention] ++ (@constraints -- [:annotation_constraints])

  defp loads(:project_input_binding), do: [:requirement, :field_definition]
  defp loads(_kind), do: []

  defp write_line!(file, value, {hash, size, count}) do
    bytes = [Jason.encode_to_iodata!(value), "\n"]
    :ok = IO.binwrite(file, bytes)
    {:crypto.hash_update(hash, bytes), size + IO.iodata_length(bytes), count}
  end

  defp row(_export, :task, row), do: row |> fields() |> Map.drop([:state, :updated_at])

  defp row(export, :question_response, row) do
    selection =
      ExportSelection
      |> Ash.Query.filter(
        export_id == ^export.id and kind == :question_response and question_response_id == ^row.id
      )
      |> Ash.read_one!(authorize?: false)

    row
    |> fields()
    |> Map.merge(%{
      effective_decision_id: selection.decision_id,
      attempt_id: row.response.attempt_id,
      submitted_at: row.response.submitted_at
    })
  end

  defp row(_export, :presentation_element, row), do: Map.put(fields(row), :element_kind, row.kind)

  defp row(export, kind, row)
       when kind in [:static_option_answer, :task_input_answer, :text_span] do
    selection =
      ExportSelection
      |> Ash.Query.filter(
        export_id == ^export.id and kind == ^kind and
          question_response_id == ^row.question_response_id
      )
      |> Ash.read_one!(authorize?: false)

    response = row.question_response.response

    fields(row)
    |> Map.merge(%{
      response_id: response.id,
      attempt_id: response.attempt_id,
      effective_decision_id: selection.decision_id
    })
  end

  defp row(_export, :question_definition, row) do
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

  defp row(_export, :project_input_binding, row) do
    fields(row)
    |> Map.merge(%{
      input_slot_id: row.requirement.input_slot_id,
      requirement_key: row.requirement.key,
      requirement_family: row.requirement.value_family,
      requirement_intended_use: row.requirement.intended_use,
      field_key: row.field_definition.key
    })
  end

  defp row(export, :dataset_value, row) do
    selected =
      ExportSelection
      |> Ash.Query.filter(
        export_id == ^export.id and kind == :dataset_value and dataset_value_id == ^row.id
      )
      |> Ash.read_one!(authorize?: false)

    row = Ash.load!(row, [:field_definition | @typed_values], authorize?: false)

    value =
      Enum.reduce(@typed_values, fields(row), fn key, result ->
        child = Map.fetch!(row, key)

        content =
          cond do
            is_nil(child) ->
              nil

            key == :asset_value ->
              asset = Ash.get!(Asset, child.asset_id, authorize?: false)

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

  defp row(_export, _kind, row), do: fields(row)

  defp fields(%resource{} = row) do
    resource
    |> Ash.Resource.Info.attributes()
    |> Enum.filter(& &1.public?)
    |> Enum.map(& &1.name)
    |> then(&Map.take(row, &1))
    |> Map.drop([:updated_at, :request_key])
    |> Map.new(fn {key, value} -> {key, exact(value)} end)
  end

  defp exact(%Decimal{} = value), do: Decimal.to_string(value, :normal)
  defp exact(value), do: value
end
