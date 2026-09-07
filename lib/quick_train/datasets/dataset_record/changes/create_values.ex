defmodule QuickTrain.Datasets.DatasetRecord.Changes.CreateValues do
  @moduledoc false

  use Ash.Resource.Change

  alias QuickTrain.Datasets.DatasetValue
  alias QuickTrain.Datasets.DatasetValue.Asset, as: AssetValue
  alias QuickTrain.Datasets.DatasetValue.Boolean, as: BooleanValue
  alias QuickTrain.Datasets.DatasetValue.DateTime, as: DateTimeValue
  alias QuickTrain.Datasets.DatasetValue.Decimal, as: DecimalValue
  alias QuickTrain.Datasets.DatasetValue.Integer, as: IntegerValue
  alias QuickTrain.Datasets.DatasetValue.Text, as: TextValue

  @impl true
  def change(changeset, _opts, _context) do
    occurrences = Ash.Changeset.get_argument(changeset, :occurrences)

    Ash.Changeset.after_action(changeset, fn _changeset, record ->
      Enum.each(occurrences, &create_occurrence!(record, &1))
      {:ok, record}
    end)
  end

  defp create_occurrence!(record, occurrence) do
    value =
      DatasetValue
      |> Ash.Changeset.for_create(:create_internal, %{
        organization_id: record.organization_id,
        dataset_id: record.dataset_id,
        schema_version_id: record.schema_version_id,
        record_type_id: record.record_type_id,
        record_id: record.id,
        field_definition_id: occurrence.field.id,
        ordinal: occurrence.ordinal
      })
      |> Ash.create!(authorize?: false)

    create_typed_value!(value.id, record.organization_id, occurrence)
  end

  defp create_typed_value!(dataset_value_id, _organization_id, %{family: :text, value: value}) do
    create_scalar!(TextValue, dataset_value_id, value)
  end

  defp create_typed_value!(dataset_value_id, _organization_id, %{family: :integer, value: value}) do
    create_scalar!(IntegerValue, dataset_value_id, value)
  end

  defp create_typed_value!(dataset_value_id, _organization_id, %{family: :decimal, value: value}) do
    create_scalar!(DecimalValue, dataset_value_id, value)
  end

  defp create_typed_value!(dataset_value_id, _organization_id, %{family: :boolean, value: value}) do
    create_scalar!(BooleanValue, dataset_value_id, value)
  end

  defp create_typed_value!(dataset_value_id, _organization_id, %{
         family: :utc_datetime,
         value: value
       }) do
    create_scalar!(DateTimeValue, dataset_value_id, value)
  end

  defp create_typed_value!(dataset_value_id, organization_id, %{family: :asset, value: asset_id}) do
    AssetValue
    |> Ash.Changeset.for_create(:create_internal, %{
      dataset_value_id: dataset_value_id,
      organization_id: organization_id,
      asset_id: asset_id
    })
    |> Ash.create!(authorize?: false)
  end

  defp create_scalar!(resource, dataset_value_id, value) do
    resource
    |> Ash.Changeset.for_create(:create_internal, %{
      dataset_value_id: dataset_value_id,
      value: value
    })
    |> Ash.create!(authorize?: false)
  end
end
