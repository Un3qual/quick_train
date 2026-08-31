defmodule QuickTrain.Datasets do
  @moduledoc "Organization-owned normalized datasets, revisions, and imports."

  use Ash.Domain, otp_app: :quick_train, extensions: [AshGraphql.Domain]

  alias QuickTrain.Datasets.{
    Dataset,
    DatasetFieldDefinition,
    DatasetRecordType,
    DatasetSchemaVersion
  }

  graphql do
    queries do
      list Dataset, :datasets, :list_scoped, relay?: true, paginate_with: :keyset
      read_one DatasetSchemaVersion, :dataset_schema_version, :get_scoped

      list DatasetRecordType, :dataset_record_types, :list_scoped,
        relay?: true,
        paginate_with: :keyset

      list DatasetFieldDefinition, :dataset_field_definitions, :list_scoped,
        relay?: true,
        paginate_with: :keyset
    end

    mutations do
      create Dataset, :create_dataset, :create_dataset

      action DatasetSchemaVersion, :create_dataset_schema_version, :create_draft,
        args: [:organization_id, :dataset_id]

      action DatasetSchemaVersion, :publish_dataset_schema_version, :publish,
        args: [:organization_id, :schema_version_id, :root_record_type_id]

      action DatasetRecordType, :add_dataset_record_type, :add_to_draft,
        args: [:organization_id, :schema_version_id, :key, :name]

      action DatasetRecordType, :update_dataset_record_type, :update_in_draft,
        args: [:organization_id, :record_type_id, :key, :name]

      action DatasetRecordType, :remove_dataset_record_type, :remove_from_draft,
        args: [:organization_id, :record_type_id]

      action DatasetFieldDefinition, :add_dataset_field_definition, :add_to_draft,
        args: [
          :organization_id,
          :record_type_id,
          :key,
          :name,
          :value_family,
          :cardinality,
          :required
        ]

      action DatasetFieldDefinition, :update_dataset_field_definition, :update_in_draft,
        args: [
          :organization_id,
          :field_definition_id,
          :key,
          :name,
          :value_family,
          :cardinality,
          :required
        ]

      action DatasetFieldDefinition, :remove_dataset_field_definition, :remove_from_draft,
        args: [:organization_id, :field_definition_id]
    end
  end

  resources do
    resource QuickTrain.Datasets.ProductCapabilities do
      define :grant_product_capabilities,
        action: :grant_to_manager,
        args: [:organization_id, :user_id]
    end

    resource QuickTrain.Datasets.Dataset do
      define :create_dataset,
        action: :create_dataset,
        args: [:organization_id, :key, :name]

      define :list_datasets, action: :list_scoped, args: [:organization_id]
    end

    resource QuickTrain.Datasets.DatasetFieldDefinition do
      define :add_field_definition,
        action: :add_to_draft,
        args: [
          :organization_id,
          :record_type_id,
          :key,
          :name,
          :value_family,
          :cardinality,
          :required
        ]

      define :update_field_definition,
        action: :update_in_draft,
        args: [
          :organization_id,
          :field_definition_id,
          :key,
          :name,
          :value_family,
          :cardinality,
          :required
        ]

      define :remove_field_definition,
        action: :remove_from_draft,
        args: [:organization_id, :field_definition_id]

      define :list_field_definitions,
        action: :list_scoped,
        args: [:organization_id, :record_type_id]
    end

    resource QuickTrain.Datasets.DatasetRecordType do
      define :add_record_type,
        action: :add_to_draft,
        args: [:organization_id, :schema_version_id, :key, :name]

      define :update_record_type,
        action: :update_in_draft,
        args: [:organization_id, :record_type_id, :key, :name]

      define :remove_record_type,
        action: :remove_from_draft,
        args: [:organization_id, :record_type_id]

      define :list_record_types,
        action: :list_scoped,
        args: [:organization_id, :schema_version_id]
    end

    resource QuickTrain.Datasets.DatasetSchemaVersion do
      define :create_schema_version,
        action: :create_draft,
        args: [:organization_id, :dataset_id]

      define :publish_schema_version,
        action: :publish,
        args: [:organization_id, :schema_version_id, :root_record_type_id]

      define :get_schema_version,
        action: :get_scoped,
        args: [:organization_id, :schema_version_id]
    end
  end
end
