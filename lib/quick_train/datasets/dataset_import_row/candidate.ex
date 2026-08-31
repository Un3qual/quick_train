defmodule QuickTrain.Datasets.DatasetImportRow.Candidate do
  @moduledoc false

  alias QuickTrain.Datasets.DatasetRecord

  def destroy!(nil), do: :ok

  def destroy!(record_id) do
    case Ash.get(DatasetRecord, record_id, authorize?: false, not_found_error?: false) do
      {:ok, nil} ->
        :ok

      {:ok, record} ->
        record =
          Ash.load!(
            record,
            [
              values: [
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

        Enum.each(record.values, &destroy_value!/1)
        Ash.destroy!(record, action: :destroy_internal, authorize?: false)
        :ok

      {:error, error} ->
        raise error
    end
  end

  defp destroy_value!(value) do
    for child <- [
          value.text_value,
          value.integer_value,
          value.decimal_value,
          value.boolean_value,
          value.date_time_value,
          value.asset_value
        ],
        not is_nil(child) do
      Ash.destroy!(child, action: :destroy_internal, authorize?: false)
    end

    Ash.destroy!(value, action: :destroy_internal, authorize?: false)
  end
end
