defmodule QuickTrain.Datasets.DatasetValue do
  @moduledoc "Stable ordinal occurrence of one exact field in a normalized record."

  alias QuickTrain.Datasets.{
    Dataset,
    DatasetFieldDefinition,
    DatasetRecord,
    DatasetRecordType,
    DatasetSchemaVersion
  }

  alias QuickTrain.Datasets.DatasetValue.{
    Asset,
    Boolean,
    DateTime,
    Decimal,
    Integer,
    Text,
    TypedChildConstraint
  }

  alias QuickTrain.Organizations.Organization

  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Datasets,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id

    attribute :ordinal, :integer do
      allow_nil? false
      public? true
      default 0
    end

    timestamps()
  end

  relationships do
    belongs_to :organization, Organization do
      allow_nil? false
      attribute_public? true
    end

    belongs_to :record, DatasetRecord do
      allow_nil? false
      attribute_public? true
    end

    belongs_to :field_definition, DatasetFieldDefinition do
      allow_nil? false
      public? true
    end

    belongs_to :record_type, DatasetRecordType do
      allow_nil? false
      attribute_public? true
    end

    belongs_to :dataset, Dataset do
      allow_nil? false
      attribute_public? true
    end

    belongs_to :schema_version, DatasetSchemaVersion do
      allow_nil? false
      attribute_public? true
    end

    has_one :text_value, Text, public?: true
    has_one :integer_value, Integer, public?: true
    has_one :decimal_value, Decimal, public?: true
    has_one :boolean_value, Boolean, public?: true
    has_one :date_time_value, DateTime, public?: true
    has_one :asset_value, Asset, public?: true
  end

  actions do
    read :read do
      primary? true

      pagination keyset?: true,
                 required?: false,
                 default_limit: 50,
                 max_page_size: 100,
                 stable_sort: [field_definition_id: :asc, ordinal: :asc, id: :asc]
    end

    create :create_internal do
      accept [
        :organization_id,
        :dataset_id,
        :schema_version_id,
        :record_type_id,
        :record_id,
        :field_definition_id,
        :ordinal
      ]
    end

    destroy :destroy_internal

    read :list_scoped do
      argument :organization_id, :uuid, allow_nil?: false
      argument :revision_id, :uuid, allow_nil?: false

      filter expr(
               organization_id == ^arg(:organization_id) and
                 record.root_revision.id == ^arg(:revision_id)
             )

      prepare build(sort: [field_definition_id: :asc, ordinal: :asc, id: :asc])

      pagination keyset?: true,
                 default_limit: 50,
                 max_page_size: 100
    end
  end

  policies do
    policy action(:read) do
      authorize_if accessing_from(Module.concat(["QuickTrain.Datasets.DatasetRecord"]), :values)
    end

    policy action(:list_scoped) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "datasets.read"}
    end
  end

  validations do
    validate compare(:ordinal, greater_than_or_equal_to: 0)
  end

  graphql do
    derive_filter? false
    derive_sort? false
    type :dataset_value

    relationships [
      :field_definition,
      :text_value,
      :integer_value,
      :decimal_value,
      :boolean_value,
      :date_time_value,
      :asset_value
    ]
  end

  postgres do
    table "dataset_values"
    repo QuickTrain.Repo
    identity_index_names record_field_ordinal: "dataset_values_record_field_ordinal_index"

    references do
      reference :organization,
        on_delete: :restrict,
        name: "dataset_values_organization_id_fkey"

      reference :dataset,
        on_delete: :restrict,
        name: "dataset_values_dataset_id_organization_id_fkey",
        match_with: [organization_id: :organization_id]

      reference :schema_version,
        on_delete: :restrict,
        name: "dataset_values_schema_version_id_dataset_id_fkey",
        match_with: [dataset_id: :dataset_id]

      reference :record_type,
        on_delete: :restrict,
        name: "dataset_values_record_type_id_schema_version_id_fkey",
        match_with: [schema_version_id: :schema_version_id]

      reference :record,
        on_delete: :restrict,
        name: "dataset_values_record_full_scope_fkey",
        match_with: [
          organization_id: :organization_id,
          dataset_id: :dataset_id,
          schema_version_id: :schema_version_id,
          record_type_id: :record_type_id
        ]

      reference :field_definition,
        on_delete: :restrict,
        name: "dataset_values_field_definition_record_type_id_fkey",
        match_with: [record_type_id: :record_type_id]
    end

    custom_indexes do
      index [:id, :organization_id],
        unique: true,
        name: "dataset_values_id_organization_id_index"

      index [:record_id, :field_definition_id, :ordinal, :id],
        name: "dataset_values_record_cursor_index"
    end

    check_constraints do
      check_constraint :ordinal, "dataset_values_ordinal_nonnegative",
        check: "ordinal >= 0",
        message: "must be nonnegative"
    end

    custom_statements do
      statement :dataset_values_validate_typed_child_function do
        after_tables TypedChildConstraint.tables()
        up TypedChildConstraint.validate_function()
        down "DROP FUNCTION IF EXISTS quick_train_validate_dataset_value(uuid);"
      end

      statement :dataset_values_enforce_typed_child_function do
        after_tables TypedChildConstraint.tables()
        up TypedChildConstraint.enforce_function()
        down "DROP FUNCTION IF EXISTS quick_train_enforce_dataset_value_typed_child();"
      end

      statement :dataset_values_typed_child_trigger do
        after_tables ["dataset_values"]
        up TypedChildConstraint.trigger("dataset_values")
        down TypedChildConstraint.drop_trigger("dataset_values")
      end

      statement :dataset_text_values_typed_child_trigger do
        after_tables ["dataset_text_values"]
        up TypedChildConstraint.trigger("dataset_text_values")
        down TypedChildConstraint.drop_trigger("dataset_text_values")
      end

      statement :dataset_integer_values_typed_child_trigger do
        after_tables ["dataset_integer_values"]
        up TypedChildConstraint.trigger("dataset_integer_values")
        down TypedChildConstraint.drop_trigger("dataset_integer_values")
      end

      statement :dataset_decimal_values_typed_child_trigger do
        after_tables ["dataset_decimal_values"]
        up TypedChildConstraint.trigger("dataset_decimal_values")
        down TypedChildConstraint.drop_trigger("dataset_decimal_values")
      end

      statement :dataset_boolean_values_typed_child_trigger do
        after_tables ["dataset_boolean_values"]
        up TypedChildConstraint.trigger("dataset_boolean_values")
        down TypedChildConstraint.drop_trigger("dataset_boolean_values")
      end

      statement :dataset_date_time_values_typed_child_trigger do
        after_tables ["dataset_date_time_values"]
        up TypedChildConstraint.trigger("dataset_date_time_values")
        down TypedChildConstraint.drop_trigger("dataset_date_time_values")
      end

      statement :dataset_asset_values_typed_child_trigger do
        after_tables ["dataset_asset_values"]
        up TypedChildConstraint.trigger("dataset_asset_values")
        down TypedChildConstraint.drop_trigger("dataset_asset_values")
      end
    end
  end

  identities do
    identity :record_field_ordinal, [:record_id, :field_definition_id, :ordinal]
  end
end
