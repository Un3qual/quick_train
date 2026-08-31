defmodule QuickTrain.Datasets.DatasetItemRevision do
  @moduledoc "Immutable schema-pinned content revision for one stable dataset item."

  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Datasets,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id

    attribute :revision_number, :integer do
      allow_nil? false
      public? true
    end

    attribute :fingerprint, :string do
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

    belongs_to :dataset, QuickTrain.Datasets.Dataset do
      allow_nil? false
      attribute_public? true
    end

    belongs_to :item, QuickTrain.Datasets.DatasetItem do
      allow_nil? false
      attribute_public? true
    end

    belongs_to :schema_version, QuickTrain.Datasets.DatasetSchemaVersion do
      allow_nil? false
      attribute_public? true
    end

    belongs_to :root_record_type, QuickTrain.Datasets.DatasetRecordType do
      allow_nil? false
      attribute_public? true
    end

    belongs_to :root_record, QuickTrain.Datasets.DatasetRecord do
      allow_nil? false
      attribute_public? true
      public? true
    end
  end

  actions do
    defaults [:read]

    action :put, :struct do
      allow_nil? false
      constraints instance_of: QuickTrain.Datasets.DatasetRevisionResult
      argument :organization_id, :uuid, allow_nil?: false
      argument :dataset_id, :uuid, allow_nil?: false
      argument :schema_version_id, :uuid, allow_nil?: false
      argument :item_id, :uuid
      argument :external_key, :string
      argument :values, {:array, :map}, allow_nil?: false
      run QuickTrain.Datasets.DatasetItemRevision.Actions.Put
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
                 offset?: false,
                 required?: true,
                 default_limit: 50,
                 max_page_size: 100
    end
  end

  policies do
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
    validate match(:fingerprint, ~r/\A[0-9a-f]{64}\z/)
  end

  graphql do
    derive_filter? false
    derive_sort? false
    type :dataset_item_revision
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
        check: "fingerprint ~ '^[0-9a-f]{64}$'",
        message: "must be exactly 64 lowercase hexadecimal characters"
    end
  end

  identities do
    identity :item_revision, [:item_id, :revision_number]
  end
end
