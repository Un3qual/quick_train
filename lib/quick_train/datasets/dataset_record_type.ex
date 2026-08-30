defmodule QuickTrain.Datasets.DatasetRecordType do
  @moduledoc "A named record shape within one dataset schema version."

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
    belongs_to :schema_version, QuickTrain.Datasets.DatasetSchemaVersion do
      allow_nil? false
      attribute_public? true
    end

    has_many :field_definitions, QuickTrain.Datasets.DatasetFieldDefinition,
      destination_attribute: :record_type_id
  end

  actions do
    defaults [:read]
  end

  graphql do
    derive_filter? false
    type :dataset_record_type
  end

  postgres do
    table "dataset_record_types"
    repo QuickTrain.Repo
    identity_index_names schema_key: "dataset_record_types_schema_key_index"

    references do
      reference :schema_version,
        on_delete: :restrict,
        name: "dataset_record_types_schema_version_id_fkey"
    end

    custom_indexes do
      index [:id, :schema_version_id],
        unique: true,
        name: "dataset_record_types_id_schema_version_id_index"

      index [:schema_version_id], name: "dataset_record_types_schema_version_id_index"
    end
  end

  identities do
    identity :schema_key, [:schema_version_id, :key]
  end
end
