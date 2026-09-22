defmodule QuickTrain.Datasets.DatasetSchemaVersion do
  @moduledoc "A draft or immutable published schema for one dataset."

  alias QuickTrain.Datasets.{Dataset, DatasetRecordType, DatasetSchemaVersion}

  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Datasets,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id

    attribute :version, :integer,
      allow_nil?: false,
      public?: true

    attribute :state, DatasetSchemaVersion.State,
      allow_nil?: false,
      public?: true,
      default: :draft

    attribute :published_at, :utc_datetime_usec, public?: true

    timestamps()
  end

  relationships do
    belongs_to :dataset, Dataset,
      allow_nil?: false,
      public?: true

    belongs_to :root_record_type, DatasetRecordType, public?: true

    has_many :record_types, DatasetRecordType,
      destination_attribute: :schema_version_id,
      public?: true
  end

  code_interface do
    define :get_internal, action: :read, get?: true, not_found_error?: false
  end

  actions do
    read :read do
      primary? true

      pagination keyset?: true,
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

    read :published_for_record_internal do
      get? true
      argument :organization_id, :uuid, allow_nil?: false
      argument :dataset_id, :uuid, allow_nil?: false
      argument :schema_version_id, :uuid, allow_nil?: false

      filter expr(
               id == ^arg(:schema_version_id) and dataset_id == ^arg(:dataset_id) and
                 dataset.organization_id == ^arg(:organization_id) and state == :published
             )
    end

    read :read_for_authoring do
      pagination keyset?: true, required?: false
    end

    create :create_draft do
      accept [:dataset_id]
      argument :organization_id, :uuid, allow_nil?: false
      change Module.concat(["QuickTrain.Datasets.Changes.AllocateSchemaVersion"])
    end

    update :publish do
      require_atomic? false
      atomic_upgrade_with :read_for_authoring
      accept []
      argument :organization_id, :uuid, allow_nil?: false
      argument :root_record_type_id, :uuid, allow_nil?: false
      change Module.concat(["QuickTrain.Datasets.Changes.DraftWrite"])
      change Module.concat(["QuickTrain.Datasets.Changes.PublishSchema"])
    end
  end

  policies do
    policy action(:read_for_authoring) do
      authorize_if context_equals(:query_for, :bulk_update)
      authorize_if context_equals(:query_for, :bulk_destroy)
    end

    policy action(:read_for_authoring) do
      forbid_unless actor_attribute_equals(:status, "active")
      authorize_if relates_to_actor_via([:dataset, :manager_role_assignments, :user])
    end

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
