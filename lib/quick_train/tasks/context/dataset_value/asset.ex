defmodule QuickTrain.Tasks.Context.DatasetValue.Asset do
  @moduledoc false
  use QuickTrain.Tasks.Context.Resource,
    source: QuickTrain.Datasets.DatasetValue.Asset,
    fields: [:id, :organization_id, :inserted_at, :updated_at, :dataset_value_id, :asset_id],
    definition?: false,
    sort: [inserted_at: :asc, id: :asc]

  relationships do
    belongs_to :asset, QuickTrain.Tasks.Context.Asset,
      source_attribute: :asset_id,
      destination_attribute: :id,
      define_attribute?: false,
      public?: true
  end

  graphql do
    type :task_dataset_asset_value
    derive_filter? false
    derive_sort? false
    relationships [:asset]
  end
end
