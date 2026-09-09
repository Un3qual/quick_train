defmodule QuickTrain.Datasets do
  @moduledoc "Organization-owned normalized datasets, revisions, and imports."

  use Ash.Domain, otp_app: :quick_train, extensions: [AshGraphql.Domain]

  alias QuickTrain.Datasets.{
    Dataset,
    DatasetFieldDefinition,
    DatasetImport,
    DatasetImportRow,
    DatasetItem,
    DatasetItemRevision,
    DatasetRecordType,
    DatasetSchemaVersion,
    DatasetValue
  }

  graphql do
    queries do
      list Dataset, :datasets, :list_scoped,
        relay?: true,
        paginate_with: :keyset,
        complexity: {__MODULE__, :connection_complexity}

      read_one DatasetSchemaVersion, :dataset_schema_version, :get_scoped

      list DatasetRecordType, :dataset_record_types, :list_scoped,
        relay?: true,
        paginate_with: :keyset,
        complexity: {__MODULE__, :connection_complexity}

      list DatasetFieldDefinition, :dataset_field_definitions, :list_scoped,
        relay?: true,
        paginate_with: :keyset,
        complexity: {__MODULE__, :connection_complexity}

      list DatasetItem, :dataset_items, :list_scoped,
        relay?: true,
        paginate_with: :keyset,
        complexity: {__MODULE__, :connection_complexity}

      list DatasetItemRevision, :dataset_item_revisions, :list_scoped,
        relay?: true,
        paginate_with: :keyset,
        complexity: {__MODULE__, :connection_complexity}

      list DatasetValue, :dataset_values, :list_scoped,
        relay?: true,
        paginate_with: :keyset,
        complexity: {__MODULE__, :connection_complexity}

      read_one DatasetImport, :dataset_import, :inspect

      list DatasetImportRow, :dataset_import_rows, :list_scoped,
        relay?: true,
        paginate_with: :keyset,
        complexity: {__MODULE__, :connection_complexity}
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

      action DatasetImport, :open_dataset_import, :open,
        args: [:organization_id, :dataset_id, :schema_version_id, :idempotency_key]

      action DatasetImportRow, :append_dataset_import_row, :append,
        args: [
          :organization_id,
          :import_id,
          :row_key,
          :external_key,
          :source_position,
          :values
        ]

      action DatasetImport, :finalize_dataset_import, :finalize,
        args: [:organization_id, :import_id]
    end
  end

  # Omitted page arguments are charged at the maximum exposed page size (100).
  def connection_complexity(arguments, child_complexity, _info) do
    page_size = arguments[:first] || arguments[:last] || 100
    1 + Kernel.max(page_size, 0) * Kernel.max(child_complexity, 1)
  end

  resources do
    resource QuickTrain.Datasets.Dataset do
      define :get_dataset, action: :read, get_by: [:id]

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
      define :get_published_record_schema,
        action: :published_for_record_internal,
        args: [:organization_id, :dataset_id, :schema_version_id],
        not_found_error?: false

      define :create_schema_version_internal, action: :create_internal

      define :publish_schema_version_internal,
        action: :publish_internal,
        get_by: [:id]

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

    resource QuickTrain.Datasets.DatasetItem do
      define :get_item_internal, action: :read, get?: true, not_found_error?: false

      define :list_items,
        action: :list_scoped,
        args: [:organization_id, :dataset_id]
    end

    resource QuickTrain.Datasets.DatasetItemRevision do
      define :put_candidate_revision,
        action: :put_candidate,
        args: [
          :organization_id,
          :dataset_id,
          :schema_version_id,
          :item_id,
          :external_key,
          :candidate_record_id
        ]

      define :put_item_revision,
        action: :put,
        args: [
          :organization_id,
          :dataset_id,
          :schema_version_id,
          :item_id,
          :external_key,
          :values
        ]

      define :list_item_revisions,
        action: :list_scoped,
        args: [:organization_id, :item_id]
    end

    resource QuickTrain.Datasets.DatasetRecord do
      define :construct_record,
        action: :construct_internal,
        args: [:organization_id, :dataset_id, :schema_version_id, :record_type_id, :occurrences]
    end

    resource QuickTrain.Datasets.DatasetValue do
      define :list_values,
        action: :list_scoped,
        args: [:organization_id, :revision_id]
    end

    resource QuickTrain.Datasets.DatasetValue.Text
    resource QuickTrain.Datasets.DatasetValue.Integer
    resource QuickTrain.Datasets.DatasetValue.Decimal
    resource QuickTrain.Datasets.DatasetValue.Boolean
    resource QuickTrain.Datasets.DatasetValue.DateTime
    resource QuickTrain.Datasets.DatasetValue.Asset

    resource QuickTrain.Datasets.DatasetImport do
      define :open_import,
        action: :open,
        args: [:organization_id, :dataset_id, :schema_version_id, :idempotency_key]

      define :finalize_import,
        action: :finalize,
        args: [:organization_id, :import_id]

      define :inspect_import,
        action: :inspect,
        args: [:organization_id, :import_id]
    end

    resource QuickTrain.Datasets.DatasetImportRow do
      define :find_import_row_conflicts,
        action: :find_conflicts_internal,
        args: [:organization_id, :import_id, :row_key, :source_position, :external_key]

      define :process_import_row, action: :process_internal, args: [:row_id]

      define :append_import_row,
        action: :append,
        args: [
          :organization_id,
          :import_id,
          :row_key,
          :external_key,
          :source_position,
          :values
        ]

      define :list_import_rows,
        action: :list_scoped,
        args: [:organization_id, :import_id]
    end
  end
end
