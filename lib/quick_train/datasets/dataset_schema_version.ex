defmodule QuickTrain.Datasets.DatasetSchemaVersion do
  @moduledoc "A draft or immutable published schema for one dataset."

  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Datasets,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key :id

    attribute :version, :integer do
      allow_nil? false
      public? true
    end

    attribute :state, :string do
      allow_nil? false
      public? true
      default "draft"
    end

    attribute :published_at, :utc_datetime_usec do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :dataset, QuickTrain.Datasets.Dataset do
      allow_nil? false
      attribute_public? true
    end

    belongs_to :root_record_type, QuickTrain.Datasets.DatasetRecordType do
      allow_nil? true
      attribute_public? true
    end

    has_many :record_types, QuickTrain.Datasets.DatasetRecordType,
      destination_attribute: :schema_version_id
  end

  actions do
    defaults [:read]
  end

  validations do
    validate compare(:version, greater_than: 0)
    validate one_of(:state, ~w(draft published))
  end

  graphql do
    derive_filter? false
    type :dataset_schema_version
  end

  postgres do
    table "dataset_schema_versions"
    repo QuickTrain.Repo
    identity_index_names dataset_version: "dataset_schema_versions_dataset_version_index"

    references do
      reference :dataset,
        on_delete: :restrict,
        name: "dataset_schema_versions_dataset_id_fkey"

      reference :root_record_type,
        on_delete: :restrict,
        name: "dataset_schema_versions_root_record_type_id_schema_id_fkey",
        match_with: [id: :schema_version_id]
    end

    custom_indexes do
      index [:dataset_id, :state], name: "dataset_schema_versions_dataset_state_index"
    end

    check_constraints do
      check_constraint :version, "dataset_schema_versions_version_positive",
        check: "version > 0",
        message: "must be positive"

      check_constraint :state, "dataset_schema_versions_state_valid",
        check: "state IN ('draft', 'published')",
        message: "is invalid"

      check_constraint :state, "dataset_schema_versions_publication_facts_valid",
        check:
          "(state = 'draft' AND published_at IS NULL) OR (state = 'published' AND published_at IS NOT NULL AND root_record_type_id IS NOT NULL)",
        message: "does not match publication facts"
    end
  end

  identities do
    identity :dataset_version, [:dataset_id, :version]
  end
end
