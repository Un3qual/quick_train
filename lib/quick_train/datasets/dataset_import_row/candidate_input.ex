defmodule QuickTrain.Datasets.DatasetImportRow.CandidateInput do
  @moduledoc false

  def from_record(record) do
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
end
