defmodule QuickTrain.Tasks.Context.DatasetValue do
  @moduledoc false
  use QuickTrain.Tasks.Context.Resource,
    source: QuickTrain.Datasets.DatasetValue,
    fields: [
      :id,
      :record_id,
      :organization_id,
      :inserted_at,
      :updated_at,
      :record_type_id,
      :field_definition_id,
      :dataset_id,
      :ordinal,
      :schema_version_id
    ],
    definition?: false,
    sort: [field_definition_id: :asc, ordinal: :asc, id: :asc]

  relationships do
    belongs_to :field_definition, QuickTrain.Tasks.Context.DatasetFieldDefinition,
      source_attribute: :field_definition_id,
      destination_attribute: :id,
      define_attribute?: false,
      public?: true

    has_one :text_value, QuickTrain.Tasks.Context.DatasetValue.Text,
      source_attribute: :id,
      destination_attribute: :dataset_value_id,
      public?: true

    has_one :integer_value, QuickTrain.Tasks.Context.DatasetValue.Integer,
      source_attribute: :id,
      destination_attribute: :dataset_value_id,
      public?: true

    has_one :decimal_value, QuickTrain.Tasks.Context.DatasetValue.Decimal,
      source_attribute: :id,
      destination_attribute: :dataset_value_id,
      public?: true

    has_one :boolean_value, QuickTrain.Tasks.Context.DatasetValue.Boolean,
      source_attribute: :id,
      destination_attribute: :dataset_value_id,
      public?: true

    has_one :date_time_value, QuickTrain.Tasks.Context.DatasetValue.DateTime,
      source_attribute: :id,
      destination_attribute: :dataset_value_id,
      public?: true

    has_one :asset_value, QuickTrain.Tasks.Context.DatasetValue.Asset,
      source_attribute: :id,
      destination_attribute: :dataset_value_id,
      public?: true
  end

  graphql do
    type :task_dataset_value
    derive_filter? false
    derive_sort? false

    relationships [
      :field_definition,
      :text_value,
      :integer_value,
      :decimal_value,
      :boolean_value,
      :date_time_value,
      :asset_value
    ]
  end
end
