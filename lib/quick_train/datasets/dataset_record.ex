defmodule QuickTrain.Datasets.DatasetRecord do
  @moduledoc "Immutable normalized record bound to one exact published record type."

  alias QuickTrain.Datasets.{
    Dataset,
    DatasetItemRevision,
    DatasetRecordType,
    DatasetSchemaVersion,
    DatasetValue
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
    timestamps()
  end

  relationships do
    belongs_to :organization, Organization,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :dataset, Dataset,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :schema_version, DatasetSchemaVersion,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :record_type, DatasetRecordType,
      allow_nil?: false,
      public?: true

    has_many :values, DatasetValue,
      destination_attribute: :record_id,
      public?: true

    has_one :root_revision, DatasetItemRevision, destination_attribute: :root_record_id
  end

  actions do
    defaults [:read]

    create :create_internal do
      accept [:organization_id, :dataset_id, :schema_version_id, :record_type_id]
    end

    create :construct_internal do
      accept [:organization_id, :dataset_id, :schema_version_id, :record_type_id]
      argument :occurrences, {:array, :map}, allow_nil?: false
      change {Module.concat(["QuickTrain.Datasets.DatasetRecord.Changes.CreateValues"]), []}
    end

    destroy :destroy_internal do
      change cascade_destroy(:values, action: :destroy_internal, after_action?: false)
    end
  end

  policies do
    policy action(:read) do
      authorize_if accessing_from(DatasetItemRevision, :root_record)
    end
  end

  graphql do
    derive_filter? false
    derive_sort? false
    type :dataset_record
    relationships [:record_type, :values]
    paginate_relationship_with values: :relay
  end

  postgres do
    table "dataset_records"
    repo QuickTrain.Repo

    references do
      reference :organization,
        on_delete: :restrict,
        name: "dataset_records_organization_id_fkey"

      reference :dataset,
        on_delete: :restrict,
        name: "dataset_records_dataset_id_organization_id_fkey",
        match_with: [organization_id: :organization_id]

      reference :schema_version,
        on_delete: :restrict,
        name: "dataset_records_schema_version_id_dataset_id_fkey",
        match_with: [dataset_id: :dataset_id]

      reference :record_type,
        on_delete: :restrict,
        name: "dataset_records_record_type_id_schema_version_id_fkey",
        match_with: [schema_version_id: :schema_version_id]
    end

    custom_indexes do
      index [:id, :organization_id, :dataset_id, :schema_version_id, :record_type_id],
        unique: true,
        name: "dataset_records_id_full_scope_index"

      index [:dataset_id, :schema_version_id, :record_type_id],
        name: "dataset_records_schema_type_index"
    end
  end
end
