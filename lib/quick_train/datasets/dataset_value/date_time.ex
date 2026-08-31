defmodule QuickTrain.Datasets.DatasetValue.DateTime do
  @moduledoc "Normalized UTC microsecond date-time representation for one occurrence."

  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Datasets,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key :id
    attribute :value, :utc_datetime_usec, allow_nil?: false, public?: true
    timestamps()
  end

  relationships do
    belongs_to :dataset_value, QuickTrain.Datasets.DatasetValue do
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
    type :dataset_date_time_value
  end

  postgres do
    table "dataset_date_time_values"
    repo QuickTrain.Repo
    identity_index_names dataset_value: "dataset_date_time_values_dataset_value_index"

    references do
      reference :dataset_value,
        on_delete: :restrict,
        name: "dataset_date_time_values_dataset_value_id_fkey"
    end
  end

  identities do
    identity :dataset_value, [:dataset_value_id]
  end
end
