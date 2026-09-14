defmodule QuickTrain.Tasks.Context.DatasetFieldDefinition do
  @moduledoc false
  use QuickTrain.Tasks.Context.Resource,
    source: QuickTrain.Datasets.DatasetFieldDefinition,
    fields: [
      :id,
      :name,
      :key,
      :required,
      :cardinality,
      :inserted_at,
      :updated_at,
      :value_family,
      :record_type_id
    ],
    definition?: true,
    sort: [inserted_at: :asc, id: :asc]

  graphql do
    type :task_dataset_field_definition
    derive_filter? false
    derive_sort? false
    relationships []
  end
end
