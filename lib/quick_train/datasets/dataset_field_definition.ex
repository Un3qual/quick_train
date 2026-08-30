defmodule QuickTrain.Datasets.DatasetFieldDefinition do
  @moduledoc "A typed single-cardinality field within one exact dataset record type."

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

    attribute :value_family, :string do
      allow_nil? false
      public? true
    end

    attribute :cardinality, :string do
      allow_nil? false
      public? true
      default "single"
    end

    attribute :required, :boolean do
      allow_nil? false
      public? true
      default false
    end

    timestamps()
  end

  relationships do
    belongs_to :record_type, QuickTrain.Datasets.DatasetRecordType do
      allow_nil? false
      attribute_public? true
    end
  end

  actions do
    defaults [:read]
  end

  validations do
    validate one_of(:value_family, ~w(text integer decimal boolean utc_datetime asset))
    validate one_of(:cardinality, ~w(single))
  end

  graphql do
    derive_filter? false
    type :dataset_field_definition
  end

  postgres do
    table "dataset_field_definitions"
    repo QuickTrain.Repo
    identity_index_names record_type_key: "dataset_field_definitions_record_type_key_index"

    references do
      reference :record_type,
        on_delete: :restrict,
        name: "dataset_field_definitions_record_type_id_fkey"
    end

    custom_indexes do
      index [:id, :record_type_id],
        unique: true,
        name: "dataset_field_definitions_id_record_type_id_index"

      index [:record_type_id], name: "dataset_field_definitions_record_type_id_index"
    end

    check_constraints do
      check_constraint :value_family, "dataset_field_definitions_value_family_valid",
        check:
          "value_family IN ('text', 'integer', 'decimal', 'boolean', 'utc_datetime', 'asset')",
        message: "is invalid"

      check_constraint :cardinality, "dataset_field_definitions_cardinality_valid",
        check: "cardinality = 'single'",
        message: "is invalid"
    end
  end

  identities do
    identity :record_type_key, [:record_type_id, :key]
  end
end
