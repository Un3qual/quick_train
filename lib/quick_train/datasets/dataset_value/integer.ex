defmodule QuickTrain.Datasets.DatasetValue.Integer do
  @moduledoc "Normalized signed integer representation for one dataset value occurrence."

  alias QuickTrain.Datasets.DatasetValue

  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Datasets,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id

    attribute :value, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: -2_147_483_648, max: 2_147_483_647]

    timestamps()
  end

  relationships do
    belongs_to :dataset_value, DatasetValue,
      allow_nil?: false,
      attribute_public?: true
  end

  actions do
    defaults [:read]

    create :create_internal do
      accept [:dataset_value_id, :value]
    end
  end

  policies do
    policy action(:read) do
      authorize_if accessing_from(
                     Module.concat(["QuickTrain.Datasets.DatasetValue"]),
                     :integer_value
                   )
    end
  end

  graphql do
    derive_filter? false
    derive_sort? false
    type :dataset_integer_value
  end

  postgres do
    table "dataset_integer_values"
    repo QuickTrain.Repo
    identity_index_names dataset_value: "dataset_integer_values_dataset_value_index"

    references do
      reference :dataset_value,
        on_delete: :restrict,
        name: "dataset_integer_values_dataset_value_id_fkey"
    end
  end

  identities do
    identity :dataset_value, [:dataset_value_id]
  end
end
