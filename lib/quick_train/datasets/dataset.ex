defmodule QuickTrain.Datasets.Dataset do
  @moduledoc "Stable organization-owned container for versioned normalized records."

  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Datasets,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key :id

    attribute :key, :string do
      allow_nil? false
      public? true
    end

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :organization, QuickTrain.Organizations.Organization do
      allow_nil? false
      attribute_public? true
    end

    has_many :schema_versions, QuickTrain.Datasets.DatasetSchemaVersion
  end

  actions do
    defaults [:read]
  end

  graphql do
    derive_filter? false
    type :dataset
  end

  postgres do
    table "datasets"
    repo QuickTrain.Repo
    identity_index_names organization_key: "datasets_organization_key_index"

    references do
      reference :organization, on_delete: :restrict, name: "datasets_organization_id_fkey"
    end

    custom_indexes do
      index [:organization_id], name: "datasets_organization_id_index"
    end
  end

  identities do
    identity :organization_key, [:organization_id, :key]
  end
end
