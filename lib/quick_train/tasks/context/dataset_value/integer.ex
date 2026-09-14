defmodule QuickTrain.Tasks.Context.DatasetValue.Integer do
  @moduledoc false
  use QuickTrain.Tasks.Context.Resource,
    source: QuickTrain.Datasets.DatasetValue.Integer,
    fields: [:id, :value, :inserted_at, :updated_at, :dataset_value_id],
    definition?: false,
    sort: [inserted_at: :asc, id: :asc]

  graphql do
    type :task_dataset_integer_value
    derive_filter? false
    derive_sort? false
    relationships []
  end
end
