defmodule QuickTrain.Datasets.DatasetValue.Text do
  @moduledoc "Normalized text representation for one dataset value occurrence."

  alias QuickTrain.Datasets.DatasetValue

  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Datasets,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      generated?: true,
      public?: true,
      writable?: false

    attribute :value, :string,
      allow_nil?: false,
      public?: true,
      constraints: [trim?: false, allow_empty?: true]

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
    bypass action(:read) do
      authorize_if QuickTrain.Tasks.ContractAccess
    end

    policy action(:read) do
      authorize_if QuickTrain.Tasks.ContractAccess.DatasetAuthority
    end

    policy action(:read) do
      authorize_if accessing_from(
                     Module.concat(["QuickTrain.Datasets.DatasetValue"]),
                     :text_value
                   )
    end
  end

  graphql do
    derive_filter? false
    derive_sort? false
    type :dataset_text_value
  end

  postgres do
    migration_defaults id: "fragment(\"gen_random_uuid()\")"
    table "dataset_text_values"
    repo QuickTrain.Repo
    identity_index_names dataset_value: "dataset_text_values_dataset_value_index"

    references do
      reference :dataset_value,
        on_delete: :restrict,
        name: "dataset_text_values_dataset_value_id_fkey"
    end
  end

  identities do
    identity :dataset_value, [:dataset_value_id]
  end
end
