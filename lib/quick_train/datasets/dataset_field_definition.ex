defmodule QuickTrain.Datasets.DatasetFieldDefinition do
  @moduledoc "A typed single-cardinality field within one exact dataset record type."

  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Datasets,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id

    attribute :key, :string do
      allow_nil? false
      public? true
    end

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :value_family, :string do
      allow_nil? false
      public? true
    end

    attribute :cardinality, :string do
      allow_nil? false
      public? true
      default "single"
    end

    attribute :required, :boolean do
      allow_nil? false
      public? true
      default false
    end

    timestamps()
  end

  relationships do
    belongs_to :record_type, QuickTrain.Datasets.DatasetRecordType do
      allow_nil? false
      attribute_public? true
    end
  end

  actions do
    defaults [:read]

    read :list_scoped do
      argument :organization_id, :uuid, allow_nil?: false
      argument :record_type_id, :uuid, allow_nil?: false

      pagination keyset?: true,
                 offset?: false,
                 required?: true,
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
      argument :key, :string, allow_nil?: false
      argument :name, :string, allow_nil?: false
      argument :value_family, :string, allow_nil?: false
      argument :cardinality, :string, allow_nil?: false
      argument :required, :boolean, allow_nil?: false
      run QuickTrain.Datasets.DatasetFieldDefinition.Actions.AddToDraft
    end

    action :update_in_draft, :struct do
      allow_nil? false
      constraints instance_of: __MODULE__
      argument :organization_id, :uuid, allow_nil?: false
      argument :field_definition_id, :uuid, allow_nil?: false
      argument :key, :string, allow_nil?: false
      argument :name, :string, allow_nil?: false
      argument :value_family, :string, allow_nil?: false
      argument :cardinality, :string, allow_nil?: false
      argument :required, :boolean, allow_nil?: false
      run QuickTrain.Datasets.DatasetFieldDefinition.Actions.UpdateInDraft
    end

    action :remove_from_draft, :atom do
      allow_nil? false
      argument :organization_id, :uuid, allow_nil?: false
      argument :field_definition_id, :uuid, allow_nil?: false
      run QuickTrain.Datasets.DatasetFieldDefinition.Actions.RemoveFromDraft
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
      require_atomic? false
      accept [:key, :name, :value_family, :cardinality, :required]
    end

    destroy :destroy_internal
  end

  policies do
    policy action(:list_scoped) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "datasets.read"}
    end

    policy action([:add_to_draft, :update_in_draft, :remove_from_draft]) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "datasets.manage"}
    end
  end

  validations do
    validate one_of(:value_family, ~w(text integer decimal boolean utc_datetime asset))
    validate one_of(:cardinality, ~w(single))
  end

  graphql do
    derive_filter? false
    derive_sort? false
    type :dataset_field_definition
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

    check_constraints do
      check_constraint :value_family, "dataset_field_definitions_value_family_valid",
        check:
          "value_family IN ('text', 'integer', 'decimal', 'boolean', 'utc_datetime', 'asset')",
        message: "is invalid"

      check_constraint :cardinality, "dataset_field_definitions_cardinality_valid",
        check: "cardinality = 'single'",
        message: "is invalid"
    end
  end

  identities do
    identity :record_type_key, [:record_type_id, :key]
  end
end
