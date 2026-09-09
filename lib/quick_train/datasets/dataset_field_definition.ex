defmodule QuickTrain.Datasets.DatasetFieldDefinition do
  @moduledoc "A typed single-cardinality field within one exact dataset record type."

  alias QuickTrain.Datasets.{DatasetFieldDefinition, DatasetRecordType, DatasetValue}

  alias QuickTrain.Datasets.SchemaVersionBoundary

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
    define :create_internal
    define :update_internal
    define :destroy_internal
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

    action :add_to_draft, :struct do
      allow_nil? false
      constraints instance_of: __MODULE__
      argument :organization_id, :uuid, allow_nil?: false
      argument :record_type_id, :uuid, allow_nil?: false

      argument :key, :string,
        allow_nil?: false,
        constraints: [match: ~r/\A[^\x00]*\z/u, max_length: 512, length_count: :bytes]

      argument :name, :string, allow_nil?: false, constraints: [match: ~r/\A[^\x00]*\z/u]
      argument :value_family, DatasetValue.Family, allow_nil?: false

      argument :cardinality, DatasetFieldDefinition.Cardinality, allow_nil?: false

      argument :required, :boolean, allow_nil?: false

      run fn input, _context ->
        %{organization_id: organization_id, record_type_id: record_type_id} = input.arguments

        SchemaVersionBoundary.with_record_type(
          organization_id,
          record_type_id,
          fn record_type ->
            attributes =
              input.arguments
              |> Map.take([:key, :name, :value_family, :cardinality, :required])
              |> Map.put(:record_type_id, record_type.id)

            __MODULE__.create_internal!(attributes, authorize?: false)
          end
        )
      end
    end

    action :update_in_draft, :struct do
      allow_nil? false
      constraints instance_of: __MODULE__
      argument :organization_id, :uuid, allow_nil?: false
      argument :field_definition_id, :uuid, allow_nil?: false

      argument :key, :string,
        allow_nil?: false,
        constraints: [match: ~r/\A[^\x00]*\z/u, max_length: 512, length_count: :bytes]

      argument :name, :string, allow_nil?: false, constraints: [match: ~r/\A[^\x00]*\z/u]
      argument :value_family, DatasetValue.Family, allow_nil?: false

      argument :cardinality, DatasetFieldDefinition.Cardinality, allow_nil?: false

      argument :required, :boolean, allow_nil?: false

      run fn input, _context ->
        %{organization_id: organization_id, field_definition_id: field_definition_id} =
          input.arguments

        SchemaVersionBoundary.with_field_definition(
          organization_id,
          field_definition_id,
          fn field ->
            attributes =
              Map.take(input.arguments, [:key, :name, :value_family, :cardinality, :required])

            __MODULE__.update_internal!(field, attributes, authorize?: false)
          end
        )
      end
    end

    action :remove_from_draft, :atom do
      allow_nil? false
      argument :organization_id, :uuid, allow_nil?: false
      argument :field_definition_id, :uuid, allow_nil?: false

      run fn input, _context ->
        %{organization_id: organization_id, field_definition_id: field_definition_id} =
          input.arguments

        SchemaVersionBoundary.with_field_definition(
          organization_id,
          field_definition_id,
          fn field ->
            __MODULE__.destroy_internal(field, authorize?: false)
          end
        )
      end
    end

    create :create_internal do
      accept [
        :record_type_id,
        :key,
        :name,
        :value_family,
        :cardinality,
        :required
      ]
    end

    update :update_internal do
      accept [:key, :name, :value_family, :cardinality, :required]
    end

    destroy :destroy_internal
  end

  policies do
    policy action(:read) do
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
    complexity {Module.concat(["QuickTrain.Datasets"]), :connection_complexity}
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
