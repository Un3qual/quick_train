defmodule QuickTrain.Datasets.DatasetFieldDefinition do
  @moduledoc "A typed single-cardinality field within one exact dataset record type."

  alias QuickTrain.Datasets.{DatasetFieldDefinition, DatasetRecordType, DatasetValue}

  alias QuickTrain.Datasets.Changes.DraftWrite

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
      public?: true,
      constraints: [match: ~r/\A[^\x00]*\z/u, max_length: 512, length_count: :bytes]

    attribute :name, :string,
      allow_nil?: false,
      public?: true,
      constraints: [match: ~r/\A[^\x00]*\z/u]

    attribute :value_family, DatasetValue.Family,
      allow_nil?: false,
      public?: true

    attribute :cardinality, DatasetFieldDefinition.Cardinality,
      allow_nil?: false,
      public?: true,
      default: :single

    attribute :required, :boolean,
      allow_nil?: false,
      public?: true,
      default: false

    timestamps()
  end

  relationships do
    belongs_to :record_type, DatasetRecordType,
      allow_nil?: false,
      public?: true
  end

  code_interface do
    define :get_internal, action: :read, get_by: [:id], not_found_error?: false
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

    read :for_record_internal do
      argument :record_type_id, :uuid, allow_nil?: false

      argument :field_keys, {:array, :string},
        allow_nil?: false,
        constraints: [items: [trim?: false, allow_empty?: true]]

      filter expr(
               record_type_id == ^arg(:record_type_id) and (required or key in ^arg(:field_keys))
             )
    end

    read :list_scoped do
      argument :organization_id, :uuid, allow_nil?: false
      argument :record_type_id, :uuid, allow_nil?: false

      pagination keyset?: true,
                 default_limit: 50,
                 max_page_size: 100

      filter expr(
               record_type_id == ^arg(:record_type_id) and
                 record_type.schema_version.dataset.organization_id ==
                   ^arg(:organization_id)
             )
    end

    read :read_for_authoring do
      pagination keyset?: true, required?: false
    end

    create :add_to_draft do
      accept [:record_type_id, :key, :name, :value_family, :cardinality, :required]
      argument :organization_id, :uuid, allow_nil?: false
      change DraftWrite
    end

    update :update_in_draft do
      require_atomic? false
      atomic_upgrade_with :read_for_authoring
      accept [:key, :name, :value_family, :cardinality, :required]
      argument :organization_id, :uuid, allow_nil?: false
      change DraftWrite
    end

    destroy :remove_from_draft do
      require_atomic? false
      atomic_upgrade_with :read_for_authoring
      argument :organization_id, :uuid, allow_nil?: false
      change DraftWrite
    end
  end

  policies do
    policy action(:read_for_authoring) do
      authorize_if context_equals(:query_for, :bulk_update)
      authorize_if context_equals(:query_for, :bulk_destroy)
    end

    policy action(:read_for_authoring) do
      forbid_unless actor_attribute_equals(:status, "active")

      authorize_if relates_to_actor_via([
                     :record_type,
                     :schema_version,
                     :dataset,
                     :manager_role_assignments,
                     :user
                   ])
    end

    policy action(:read) do
      authorize_if Module.concat(["QuickTrain.Authorization.Checks.CollectionContext"])
      authorize_if Module.concat(["QuickTrain.Authorization.Checks.SourceRead"])
    end

    policy action(:read) do
      authorize_if Module.concat(["QuickTrain.Authorization.Checks.CollectionContext"])

      authorize_if accessing_from(
                     Module.concat(["QuickTrain.Datasets.DatasetRecordType"]),
                     :field_definitions
                   )

      authorize_if accessing_from(
                     Module.concat(["QuickTrain.Datasets.DatasetValue"]),
                     :field_definition
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
    type :dataset_field_definition
    relationships [:record_type]
  end

  postgres do
    table "dataset_field_definitions"
    repo QuickTrain.Repo
    identity_index_names record_type_key: "dataset_field_definitions_record_type_key_index"

    references do
      reference :record_type,
        on_delete: :restrict,
        name: "dataset_field_definitions_record_type_id_fkey"
    end

    custom_indexes do
      index [:id, :record_type_id],
        unique: true,
        name: "dataset_field_definitions_id_record_type_id_index"

      index [:record_type_id], name: "dataset_field_definitions_record_type_id_index"
    end
  end

  identities do
    identity :record_type_key, [:record_type_id, :key]
  end
end
