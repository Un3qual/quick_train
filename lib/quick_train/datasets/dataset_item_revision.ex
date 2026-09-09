defmodule QuickTrain.Datasets.DatasetItemRevision do
  @moduledoc "Immutable schema-pinned content revision for one stable dataset item."

  alias QuickTrain.Datasets.{
    Dataset,
    DatasetItem,
    DatasetRecord,
    DatasetRecordType,
    DatasetSchemaVersion
  }

  alias QuickTrain.Datasets.DatasetItemRevision.Result
  alias QuickTrain.Organizations.Organization

  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Datasets,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id

    attribute :revision_number, :integer,
      allow_nil?: false,
      public?: true

    attribute :fingerprint, :binary,
      allow_nil?: false,
      public?: true

    timestamps()
  end

  relationships do
    belongs_to :organization, Organization,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :dataset, Dataset,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :item, DatasetItem,
      allow_nil?: false,
      public?: true

    belongs_to :schema_version, DatasetSchemaVersion,
      allow_nil?: false,
      public?: true

    belongs_to :root_record_type, DatasetRecordType,
      allow_nil?: false,
      public?: true

    belongs_to :root_record, DatasetRecord,
      allow_nil?: false,
      public?: true
  end

  actions do
    read :read do
      primary? true

      pagination keyset?: true,
                 required?: false,
                 default_limit: 50,
                 max_page_size: 100,
                 stable_sort: [revision_number: :desc, id: :desc]
    end

    action :put, :struct do
      allow_nil? false
      constraints instance_of: Result
      argument :organization_id, :uuid, allow_nil?: false
      argument :dataset_id, :uuid, allow_nil?: false
      argument :schema_version_id, :uuid, allow_nil?: false
      argument :item_id, :uuid
      argument :external_key, :string
      argument :values, {:array, :map}, allow_nil?: false

      validate present([:item_id, :external_key], at_least: 1) do
        message "missing_item_identity"
      end

      validate match(:external_key, ~r/\S/) do
        where present(:external_key)
        message "missing_item_identity"
      end

      run {Module.concat(["QuickTrain.Datasets.DatasetItemRevision.Actions.Put"]), []}
    end

    action :put_candidate, :struct do
      allow_nil? false
      constraints instance_of: Result
      argument :organization_id, :uuid, allow_nil?: false
      argument :dataset_id, :uuid, allow_nil?: false
      argument :schema_version_id, :uuid, allow_nil?: false
      argument :item_id, :uuid
      argument :external_key, :string
      argument :candidate_record_id, :uuid, allow_nil?: false
      validate present([:item_id, :external_key], at_least: 1)
      run {Module.concat(["QuickTrain.Datasets.DatasetItemRevision.Actions.Put"]), []}
    end

    create :create_internal do
      accept [
        :organization_id,
        :dataset_id,
        :item_id,
        :schema_version_id,
        :root_record_type_id,
        :root_record_id,
        :revision_number,
        :fingerprint
      ]
    end

    read :list_scoped do
      argument :organization_id, :uuid, allow_nil?: false
      argument :item_id, :uuid, allow_nil?: false
      filter expr(organization_id == ^arg(:organization_id) and item_id == ^arg(:item_id))
      prepare build(sort: [revision_number: :desc, id: :desc])

      pagination keyset?: true,
                 default_limit: 50,
                 max_page_size: 100
    end
  end

  policies do
    policy action(:read) do
      authorize_if accessing_from(
                     Module.concat(["QuickTrain.Datasets.DatasetItem"]),
                     :revisions
                   )

      authorize_if accessing_from(
                     Module.concat(["QuickTrain.Datasets.DatasetImportRow"]),
                     :item_revision
                   )
    end

    policy action(:put) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "datasets.manage"}
    end

    policy action(:list_scoped) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "datasets.read"}
    end
  end

  validations do
    validate compare(:revision_number, greater_than: 0)
  end

  graphql do
    complexity {Module.concat(["QuickTrain.Datasets"]), :connection_complexity}
    attribute_types fingerprint: :string
    derive_filter? false
    derive_sort? false
    type :dataset_item_revision
    relationships [:item, :schema_version, :root_record_type, :root_record]
  end

  postgres do
    table "dataset_item_revisions"
    repo QuickTrain.Repo
    identity_index_names item_revision: "dataset_item_revisions_item_revision_index"

    references do
      reference :organization,
        on_delete: :restrict,
        name: "dataset_item_revisions_organization_id_fkey"

      reference :dataset,
        on_delete: :restrict,
        name: "dataset_item_revisions_dataset_id_organization_id_fkey",
        match_with: [organization_id: :organization_id]

      reference :item,
        on_delete: :restrict,
        name: "dataset_item_revisions_item_scope_fkey",
        match_with: [dataset_id: :dataset_id, organization_id: :organization_id]

      reference :schema_version,
        on_delete: :restrict,
        name: "dataset_item_revisions_schema_designated_root_fkey",
        match_with: [
          dataset_id: :dataset_id,
          root_record_type_id: :root_record_type_id
        ]

      reference :root_record_type,
        on_delete: :restrict,
        name: "dataset_item_revisions_root_type_schema_fkey",
        match_with: [schema_version_id: :schema_version_id]

      reference :root_record,
        on_delete: :restrict,
        name: "dataset_item_revisions_root_record_scope_fkey",
        match_with: [
          organization_id: :organization_id,
          dataset_id: :dataset_id,
          schema_version_id: :schema_version_id,
          root_record_type_id: :record_type_id
        ]
    end

    custom_indexes do
      index [:id, :dataset_id, :organization_id],
        unique: true,
        name: "dataset_item_revisions_id_dataset_organization_index"

      index [:item_id, :revision_number, :id],
        name: "dataset_item_revisions_item_cursor_index"

      index [:id, :item_id, :dataset_id],
        unique: true,
        name: "dataset_item_revisions_id_item_dataset_index"
    end

    check_constraints do
      check_constraint :revision_number, "dataset_item_revisions_revision_positive",
        check: "revision_number > 0",
        message: "must be positive"

      check_constraint :fingerprint, "dataset_item_revisions_fingerprint_format",
        check: "octet_length(fingerprint) = 32",
        message: "must be exactly 32 bytes"
    end
  end

  identities do
    identity :item_revision, [:item_id, :revision_number]
  end
end
