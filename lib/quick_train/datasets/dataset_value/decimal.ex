defmodule QuickTrain.Datasets.DatasetValue.Decimal do
  @moduledoc "Normalized arbitrary-precision decimal representation for one occurrence."

  alias QuickTrain.Datasets.DatasetValue

  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Datasets,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key :id
    attribute :value, :decimal, allow_nil?: false, public?: true
    timestamps()
  end

  relationships do
    belongs_to :dataset_value, DatasetValue do
      allow_nil? false
      attribute_public? true
    end
  end

  actions do
    defaults [:read]

    create :create_internal do
      accept [:dataset_value_id, :value]
    end

    destroy :destroy_internal
  end

  graphql do
    derive_filter? false
    derive_sort? false
    type :dataset_decimal_value
  end

  postgres do
    table "dataset_decimal_values"
    repo QuickTrain.Repo
    identity_index_names dataset_value: "dataset_decimal_values_dataset_value_index"

    references do
      reference :dataset_value,
        on_delete: :restrict,
        name: "dataset_decimal_values_dataset_value_id_fkey"
    end
  end

  identities do
    identity :dataset_value, [:dataset_value_id]
  end
end
