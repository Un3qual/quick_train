defmodule QuickTrain.Datasets.DatasetImportRow do
  @moduledoc "Immutable accepted row provenance and its terminal processing outcome."

  alias QuickTrain.Datasets.{
    Dataset,
    DatasetImport,
    DatasetItemRevision,
    DatasetRecord,
    DatasetRecordType,
    DatasetSchemaVersion
  }

  alias QuickTrain.Datasets.DatasetImportRow.ValueInput
  alias QuickTrain.Organizations.Organization

  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Datasets,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id
    attribute :row_key, :string, allow_nil?: false, public?: true
    attribute :source_position, :integer, allow_nil?: false, public?: true
    attribute :external_key, :string, public?: true
    attribute :fingerprint, QuickTrain.Types.Sha256Digest, allow_nil?: false

    attribute :outcome, QuickTrain.Datasets.DatasetImportRow.Outcome,
      allow_nil?: false,
      default: :pending,
      public?: true

    attribute :error_code, :string, public?: true
    timestamps()
  end

  relationships do
    belongs_to :organization, Organization,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :dataset, Dataset,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :import, DatasetImport,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :schema_version, DatasetSchemaVersion,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :root_record_type, DatasetRecordType,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :candidate_record, DatasetRecord, attribute_public?: true

    belongs_to :item_revision, DatasetItemRevision, public?: true
  end

  actions do
    read :read do
      primary? true

      pagination keyset?: true,
                 required?: false,
                 default_limit: 50,
                 max_page_size: 100,
                 stable_sort: [source_position: :asc, id: :asc]
    end

    action :append, :struct do
      allow_nil? false
      constraints instance_of: __MODULE__
      argument :organization_id, :uuid, allow_nil?: false
      argument :import_id, :uuid, allow_nil?: false
      argument :row_key, :string, allow_nil?: false
      argument :external_key, :string
      argument :source_position, :integer, allow_nil?: false

      argument :values, {:array, ValueInput}, allow_nil?: false

      run {Module.concat(["QuickTrain.Datasets.DatasetImportRow.Actions.Append"]), []}
    end

    read :list_scoped do
      argument :organization_id, :uuid, allow_nil?: false
      argument :import_id, :uuid, allow_nil?: false
      filter expr(organization_id == ^arg(:organization_id) and import_id == ^arg(:import_id))
      prepare build(sort: [source_position: :asc, id: :asc])

      pagination keyset?: true,
                 default_limit: 50,
                 max_page_size: 100
    end

    create :create_internal do
      accept [
        :organization_id,
        :dataset_id,
        :import_id,
        :schema_version_id,
        :root_record_type_id,
        :candidate_record_id,
        :row_key,
        :source_position,
        :external_key,
        :fingerprint,
        :outcome,
        :error_code
      ]
    end

    update :complete_internal do
      accept [:outcome, :error_code, :item_revision_id]
    end

    destroy :destroy_internal
  end

  policies do
    policy action(:read) do
      authorize_if accessing_from(Module.concat(["QuickTrain.Datasets.DatasetImport"]), :rows)
    end

    policy action([:append, :list_scoped]) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "dataset_imports.manage"}
    end
  end

  validations do
    validate compare(:source_position, greater_than_or_equal_to: 0)
  end

  graphql do
    derive_filter? false
    derive_sort? false
    type :dataset_import_row
    relationships [:item_revision]
  end

  postgres do
    table "dataset_import_rows"
    repo QuickTrain.Repo
    identity_index_names import_row_key: "dataset_import_rows_import_row_key_index"

    references do
      reference :organization,
        on_delete: :restrict,
        name: "dataset_import_rows_organization_id_fkey"

      reference :dataset,
        on_delete: :restrict,
        name: "dataset_import_rows_dataset_scope_fkey",
        match_with: [organization_id: :organization_id]

      reference :import,
        on_delete: :restrict,
        name: "dataset_import_rows_import_scope_fkey",
        match_with: [
          organization_id: :organization_id,
          dataset_id: :dataset_id,
          schema_version_id: :schema_version_id
        ]

      reference :schema_version,
        on_delete: :restrict,
        name: "dataset_import_rows_schema_root_scope_fkey",
        match_with: [dataset_id: :dataset_id, root_record_type_id: :root_record_type_id]

      reference :root_record_type,
        on_delete: :restrict,
        name: "dataset_import_rows_root_type_schema_fkey",
        match_with: [schema_version_id: :schema_version_id]

      reference :candidate_record,
        on_delete: :restrict,
        name: "dataset_import_rows_candidate_record_scope_fkey",
        match_with: [
          organization_id: :organization_id,
          dataset_id: :dataset_id,
          schema_version_id: :schema_version_id,
          root_record_type_id: :record_type_id
        ]

      reference :item_revision,
        on_delete: :restrict,
        name: "dataset_import_rows_item_revision_scope_fkey",
        match_with: [dataset_id: :dataset_id, organization_id: :organization_id]
    end

    custom_indexes do
      index [:import_id, :source_position],
        unique: true,
        name: "dataset_import_rows_import_source_position_index"

      index [:import_id, :external_key],
        unique: true,
        where: "external_key IS NOT NULL",
        name: "dataset_import_rows_import_external_key_index"

      index [:import_id, :outcome, :source_position, :id],
        name: "dataset_import_rows_outcome_cursor_index"
    end

    check_constraints do
      check_constraint :source_position, "dataset_import_rows_source_position_nonnegative",
        check: "source_position >= 0",
        message: "must be nonnegative"

      check_constraint :outcome, "dataset_import_rows_outcome_valid",
        check: "outcome IN ('pending', 'succeeded', 'unchanged', 'failed')",
        message: "is invalid"

      check_constraint :outcome, "dataset_import_rows_outcome_facts_valid",
        check:
          "(outcome = 'pending' AND candidate_record_id IS NOT NULL AND item_revision_id IS NULL AND error_code IS NULL) OR " <>
            "(outcome IN ('succeeded', 'unchanged') AND candidate_record_id IS NOT NULL AND item_revision_id IS NOT NULL AND error_code IS NULL) OR " <>
            "(outcome = 'failed' AND item_revision_id IS NULL AND error_code IS NOT NULL)",
        message: "does not match outcome facts"

      check_constraint :fingerprint, "dataset_import_rows_fingerprint_format",
        check: "octet_length(fingerprint) = 32",
        message: "must be exactly 32 bytes"
    end
  end

  identities do
    identity :import_row_key, [:import_id, :row_key]
  end
end
