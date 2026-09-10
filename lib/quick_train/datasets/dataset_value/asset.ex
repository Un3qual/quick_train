defmodule QuickTrain.Datasets.DatasetValue.Asset do
  @moduledoc "Organization-safe immutable asset representation for one occurrence."

  alias QuickTrain.Assets.Asset, as: StoredAsset
  alias QuickTrain.Datasets.DatasetValue
  alias QuickTrain.Organizations.Organization

  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Datasets,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id
    timestamps()
  end

  relationships do
    belongs_to :organization, Organization,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :dataset_value, DatasetValue,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :asset, StoredAsset,
      allow_nil?: false,
      public?: true
  end

  actions do
    defaults [:read]

    create :create_internal do
      accept [:organization_id, :dataset_value_id, :asset_id]
    end
  end

  policies do
    policy action(:read) do
      authorize_if accessing_from(
                     Module.concat(["QuickTrain.Datasets.DatasetValue"]),
                     :asset_value
                   )
    end
  end

  graphql do
    derive_filter? false
    derive_sort? false
    type :dataset_asset_value
    relationships [:asset]
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
