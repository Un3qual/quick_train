defmodule QuickTrain.Datasets.DatasetAssetValue do
  @moduledoc "Organization-safe immutable asset representation for one occurrence."

  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Datasets,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key :id
    timestamps()
  end

  relationships do
    belongs_to :organization, QuickTrain.Organizations.Organization do
      allow_nil? false
      attribute_public? true
    end

    belongs_to :dataset_value, QuickTrain.Datasets.DatasetValue do
      allow_nil? false
      attribute_public? true
    end

    belongs_to :asset, QuickTrain.Assets.Asset do
      allow_nil? false
      attribute_public? true
    end
  end

  actions do
    defaults [:read]

    create :create_internal do
      accept [:organization_id, :dataset_value_id, :asset_id]
    end
  end

  graphql do
    derive_filter? false
    derive_sort? false
    type :dataset_asset_value
  end

  postgres do
    table "dataset_asset_values"
    repo QuickTrain.Repo
    identity_index_names dataset_value: "dataset_asset_values_dataset_value_index"

    references do
      reference :organization,
        on_delete: :restrict,
        name: "dataset_asset_values_organization_id_fkey"

      reference :dataset_value,
        on_delete: :restrict,
        name: "dataset_asset_values_dataset_value_id_organization_id_fkey",
        match_with: [organization_id: :organization_id]

      reference :asset,
        on_delete: :restrict,
        name: "dataset_asset_values_asset_id_organization_id_fkey",
        match_with: [organization_id: :organization_id]
    end
  end

  identities do
    identity :dataset_value, [:dataset_value_id]
  end
end
