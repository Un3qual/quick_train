defmodule QuickTrain.Datasets.DatasetImportRow.Process do
  @moduledoc false

  require Ash.Query

  alias QuickTrain.Datasets.{DatasetImportRow, DatasetRecord}

  def process(row_id) do
    Ash.transact([DatasetImportRow, DatasetRecord], fn ->
      case locked_row(row_id) do
        nil ->
          :missing

        %{outcome: outcome} when outcome != :pending ->
          :terminal

        row ->
          create_revision_and_complete(row)
      end
    end)
  end

  def terminalize(row_id, error_code \\ "processing_retries_exhausted") do
    Ash.transact(DatasetImportRow, fn ->
      case locked_row(row_id) do
        %{outcome: :pending} = row ->
          row
          |> Ash.Changeset.for_update(:complete_internal, %{
            outcome: :failed,
            error_code: error_code,
            item_revision_id: nil
          })
          |> Ash.update!(authorize?: false)

          :terminalized

        _other ->
          :skipped
      end
    end)
  end

  defp create_revision_and_complete(row) do
    record = Ash.get!(DatasetRecord, row.candidate_record_id, authorize?: false)
    values = values_from_record(record)

    result =
      QuickTrain.Datasets.put_item_revision!(
        row.organization_id,
        row.dataset_id,
        row.schema_version_id,
        if(row.external_key, do: nil, else: row.id),
        row.external_key,
        values,
        authorize?: false
      )

    outcome = if result.changed, do: :succeeded, else: :unchanged

    row
    |> Ash.Changeset.for_update(:complete_internal, %{
      outcome: outcome,
      error_code: nil,
      item_revision_id: result.revision.id
    })
    |> Ash.update!(authorize?: false)
  end

  defp values_from_record(record) do
    record =
      Ash.load!(
        record,
        [
          values: [
            :field_definition,
            :text_value,
            :integer_value,
            :decimal_value,
            :boolean_value,
            :date_time_value,
            :asset_value
          ]
        ],
        authorize?: false
      )

    Enum.map(record.values, fn value ->
      key = value.field_definition.key

      case value.field_definition.value_family do
        :text -> %{field: key, text: value.text_value.value}
        :integer -> %{field: key, integer: value.integer_value.value}
        :decimal -> %{field: key, decimal: value.decimal_value.value}
        :boolean -> %{field: key, boolean: value.boolean_value.value}
        :utc_datetime -> %{field: key, utc_datetime: value.date_time_value.value}
        :asset -> %{field: key, asset_id: value.asset_value.asset_id}
      end
    end)
  end

  defp locked_row(row_id) do
    DatasetImportRow
    |> Ash.Query.filter(id == ^row_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(authorize?: false)
  end
end
