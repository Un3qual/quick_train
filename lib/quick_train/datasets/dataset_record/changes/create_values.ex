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
      scope =
        record
        |> Map.take([:organization_id, :dataset_id, :schema_version_id, :record_type_id])
        |> Map.put(:record_id, record.id)

      inputs =
        Enum.map(occurrences, fn occurrence ->
          Map.merge(scope, %{
            field_definition_id: occurrence.field.id,
            ordinal: occurrence.ordinal
          })
        end)

      values = bulk_create!(DatasetValue, inputs, return_records?: true, sorted?: true)

      occurrences
      |> Enum.zip(values.records)
      |> Enum.group_by(fn {occurrence, _value} -> occurrence.family end)
      |> Enum.each(fn {family, entries} ->
        inputs = Enum.map(entries, &child_attributes(&1, record.organization_id))

        bulk_create!(typed_resource(family), inputs)
      end)

      {:ok, record}
    end)
  end

  defp bulk_create!(resource, inputs, opts \\ []) do
    Ash.bulk_create!(
      inputs,
      resource,
      :create_internal,
      Keyword.merge(
        [authorize?: false, return_errors?: true, stop_on_error?: true, transaction: :all],
        opts
      )
    )
  end

  defp child_attributes({%{family: :asset, value: asset_id}, value}, organization_id) do
    %{dataset_value_id: value.id, organization_id: organization_id, asset_id: asset_id}
  end

  defp child_attributes({occurrence, value}, _organization_id) do
    %{dataset_value_id: value.id, value: occurrence.value}
  end

  defp typed_resource(:text), do: TextValue
  defp typed_resource(:integer), do: IntegerValue
  defp typed_resource(:decimal), do: DecimalValue
  defp typed_resource(:boolean), do: BooleanValue
  defp typed_resource(:utc_datetime), do: DateTimeValue
  defp typed_resource(:asset), do: AssetValue
end
