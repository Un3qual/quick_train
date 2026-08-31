defmodule QuickTrain.Datasets.DatasetRecordType do
  @moduledoc "A named record shape within one dataset schema version."

  alias QuickTrain.Datasets.{DatasetFieldDefinition, DatasetSchemaVersion}

  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Datasets,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id

    attribute :key, :string,
      allow_nil?: false,
      public?: true

    attribute :name, :string,
      allow_nil?: false,
      public?: true

    timestamps()
  end

  relationships do
    belongs_to :schema_version, DatasetSchemaVersion,
      allow_nil?: false,
      public?: true

    has_many :field_definitions, DatasetFieldDefinition,
      destination_attribute: :record_type_id,
      public?: true
  end

  actions do
    read :read do
      primary? true

      pagination keyset?: true,
                 required?: false,
                 default_limit: 50,
                 max_page_size: 100,
                 stable_sort: [inserted_at: :asc, id: :asc]
    end

    read :list_scoped do
      argument :organization_id, :uuid, allow_nil?: false
      argument :schema_version_id, :uuid, allow_nil?: false

      pagination keyset?: true,
                 default_limit: 50,
                 max_page_size: 100

      filter expr(
               schema_version_id == ^arg(:schema_version_id) and
                 schema_version.dataset.organization_id == ^arg(:organization_id)
             )
    end

    action :add_to_draft, :struct do
      allow_nil? false
      constraints instance_of: __MODULE__
      argument :organization_id, :uuid, allow_nil?: false
      argument :schema_version_id, :uuid, allow_nil?: false
      argument :key, :string, allow_nil?: false
      argument :name, :string, allow_nil?: false
      run {Module.concat(["QuickTrain.Datasets.DatasetRecordType.Actions.AddToDraft"]), []}
    end

    action :update_in_draft, :struct do
      allow_nil? false
      constraints instance_of: __MODULE__
      argument :organization_id, :uuid, allow_nil?: false
      argument :record_type_id, :uuid, allow_nil?: false
      argument :key, :string, allow_nil?: false
      argument :name, :string, allow_nil?: false
      run {Module.concat(["QuickTrain.Datasets.DatasetRecordType.Actions.UpdateInDraft"]), []}
    end

    action :remove_from_draft, :atom do
      allow_nil? false
      argument :organization_id, :uuid, allow_nil?: false
      argument :record_type_id, :uuid, allow_nil?: false
      run {Module.concat(["QuickTrain.Datasets.DatasetRecordType.Actions.RemoveFromDraft"]), []}
    end

    create :create_internal do
      accept [:schema_version_id, :key, :name]
    end

    update :update_internal do
      accept [:key, :name]
    end

    destroy :destroy_internal
  end

  policies do
    policy action(:read) do
      authorize_if accessing_from(
                     Module.concat(["QuickTrain.Datasets.DatasetSchemaVersion"]),
                     :root_record_type
                   )

      authorize_if accessing_from(
                     Module.concat(["QuickTrain.Datasets.DatasetSchemaVersion"]),
                     :record_types
                   )

      authorize_if accessing_from(
                     Module.concat(["QuickTrain.Datasets.DatasetFieldDefinition"]),
                     :record_type
                   )

      authorize_if accessing_from(
                     Module.concat(["QuickTrain.Datasets.DatasetItemRevision"]),
                     :root_record_type
                   )

      authorize_if accessing_from(
                     Module.concat(["QuickTrain.Datasets.DatasetRecord"]),
                     :record_type
                   )
    end

    policy action(:list_scoped) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "datasets.read"}
    end

    policy action([:add_to_draft, :update_in_draft, :remove_from_draft]) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "datasets.manage"}
    end
  end

  graphql do
    derive_filter? false
    derive_sort? false
    type :dataset_record_type
    relationships [:schema_version, :field_definitions]
    paginate_relationship_with field_definitions: :relay
  end

  postgres do
    table "dataset_record_types"
    repo QuickTrain.Repo
    identity_index_names schema_key: "dataset_record_types_schema_key_index"

    references do
      reference :schema_version,
        on_delete: :restrict,
        name: "dataset_record_types_schema_version_id_fkey"
    end

    custom_indexes do
      index [:id, :schema_version_id],
        unique: true,
        name: "dataset_record_types_id_schema_version_id_index"

      index [:schema_version_id], name: "dataset_record_types_schema_version_id_index"
    end
  end

  identities do
    identity :schema_key, [:schema_version_id, :key]
  end
end
