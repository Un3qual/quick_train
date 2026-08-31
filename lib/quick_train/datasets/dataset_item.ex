defmodule QuickTrain.Datasets.DatasetItem do
  @moduledoc "Stable identity for one item within an organization dataset."

  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Datasets,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :external_key, :string, public?: true
    timestamps()
  end

  relationships do
    belongs_to :organization, QuickTrain.Organizations.Organization do
      allow_nil? false
      attribute_public? true
    end

    belongs_to :dataset, QuickTrain.Datasets.Dataset do
      allow_nil? false
      attribute_public? true
    end

    has_many :revisions, QuickTrain.Datasets.DatasetItemRevision, destination_attribute: :item_id
  end

  actions do
    defaults [:read]
  end

  graphql do
    derive_filter? false
    derive_sort? false
    type :dataset_item
  end

  postgres do
    table "dataset_items"
    repo QuickTrain.Repo

    references do
      reference :organization,
        on_delete: :restrict,
        name: "dataset_items_organization_id_fkey"

      reference :dataset,
        on_delete: :restrict,
        name: "dataset_items_dataset_id_organization_id_fkey",
        match_with: [organization_id: :organization_id]
    end

    custom_indexes do
      index [:id, :dataset_id, :organization_id],
        unique: true,
        name: "dataset_items_id_dataset_organization_index"

      index [:dataset_id, :external_key],
        unique: true,
        where: "external_key IS NOT NULL",
        name: "dataset_items_dataset_external_key_index"

      index [:dataset_id, :inserted_at, :id], name: "dataset_items_dataset_cursor_index"
    end
  end
end
