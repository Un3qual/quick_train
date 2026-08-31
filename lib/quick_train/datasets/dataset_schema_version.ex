defmodule QuickTrain.Datasets.DatasetSchemaVersion do
  @moduledoc "A draft or immutable published schema for one dataset."

  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Datasets,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id

    attribute :version, :integer do
      allow_nil? false
      public? true
    end

    attribute :state, QuickTrain.Datasets.DatasetSchemaState do
      allow_nil? false
      public? true
      default :draft
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
      public? true
    end

    belongs_to :root_record_type, QuickTrain.Datasets.DatasetRecordType do
      allow_nil? true
      attribute_public? true
      public? true
    end

    has_many :record_types, QuickTrain.Datasets.DatasetRecordType do
      destination_attribute :schema_version_id
      public? true
    end
  end

  actions do
    read :read do
      primary? true

      pagination keyset?: true,
                 offset?: false,
                 required?: false,
                 default_limit: 50,
                 max_page_size: 100,
                 stable_sort: [version: :desc, id: :desc]
    end

    read :get_scoped do
      get? true
      argument :organization_id, :uuid, allow_nil?: false
      argument :schema_version_id, :uuid, allow_nil?: false

      filter expr(
               id == ^arg(:schema_version_id) and
                 dataset.organization_id == ^arg(:organization_id)
             )
    end

    action :create_draft, :struct do
      allow_nil? false
      constraints instance_of: __MODULE__
      argument :organization_id, :uuid, allow_nil?: false
      argument :dataset_id, :uuid, allow_nil?: false
      run {Module.concat(["QuickTrain.Datasets.DatasetSchemaVersion.Actions.CreateDraft"]), []}
    end

    action :publish, :struct do
      allow_nil? false
      constraints instance_of: __MODULE__
      argument :organization_id, :uuid, allow_nil?: false
      argument :schema_version_id, :uuid, allow_nil?: false
      argument :root_record_type_id, :uuid, allow_nil?: false
      run {Module.concat(["QuickTrain.Datasets.DatasetSchemaVersion.Actions.Publish"]), []}
    end

    create :create_internal do
      accept [:dataset_id, :version]
      change set_attribute(:state, :draft)
    end

    update :publish_internal do
      accept [:root_record_type_id, :published_at]
      validate attribute_equals(:state, :draft)
      change set_attribute(:state, :published)
    end
  end

  policies do
    policy action(:read) do
      authorize_if accessing_from(
                     Module.concat(["QuickTrain.Datasets.Dataset"]),
                     :schema_versions
                   )

      authorize_if accessing_from(
                     Module.concat(["QuickTrain.Datasets.DatasetRecordType"]),
                     :schema_version
                   )

      authorize_if accessing_from(
                     Module.concat(["QuickTrain.Datasets.DatasetItemRevision"]),
                     :schema_version
                   )

      authorize_if accessing_from(
                     Module.concat(["QuickTrain.Datasets.DatasetImport"]),
                     :schema_version
                   )
    end

    policy action(:get_scoped) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "datasets.read"}
    end

    policy action([:create_draft, :publish]) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "datasets.manage"}
    end
  end

  validations do
    validate compare(:version, greater_than: 0)
  end

  graphql do
    derive_filter? false
    derive_sort? false
    type :dataset_schema_version
    relationships [:dataset, :root_record_type, :record_types]
    paginate_relationship_with record_types: :relay
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
      index [:id, :dataset_id],
        unique: true,
        name: "dataset_schema_versions_id_dataset_id_index"

      index [:id, :dataset_id, :root_record_type_id],
        unique: true,
        name: "dataset_schema_versions_id_dataset_root_index"

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
