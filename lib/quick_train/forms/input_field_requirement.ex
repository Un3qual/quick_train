defmodule QuickTrain.Forms.InputFieldRequirement do
  @moduledoc "Organization-scoped input field requirement definition."
  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Forms,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id

    attribute :key, QuickTrain.Forms.PlainText,
      public?: true,
      allow_nil?: false,
      constraints: [
        trim?: false,
        allow_empty?: true,
        match: ~r/\A[^\x00]*\z/u,
        max_length: 512,
        length_count: :bytes,
        min_length: 1
      ]

    attribute :value_family, QuickTrain.Forms.InputValueFamily,
      public?: true,
      allow_nil?: false

    attribute :cardinality, QuickTrain.Forms.FieldCardinality,
      public?: true,
      allow_nil?: false,
      default: :single

    attribute :required, :boolean, public?: true, allow_nil?: false
    attribute :intended_use, QuickTrain.Forms.AssetIntendedUse, public?: true
    timestamps()
  end

  relationships do
    belongs_to :input_slot, QuickTrain.Forms.InputSlotDefinition,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :version, QuickTrain.Forms.FormVersion, allow_nil?: false, attribute_public?: true
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
      filter expr(version.form.organization_id == ^arg(:organization_id))

      pagination keyset?: true,
                 required?: true,
                 default_limit: 50,
                 max_page_size: 100,
                 stable_sort: [inserted_at: :asc, id: :asc]
    end

    read :get_scoped do
      get? true
      argument :organization_id, :uuid, allow_nil?: false
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id) and version.form.organization_id == ^arg(:organization_id))
    end

    action :add_to_draft, :struct do
      allow_nil? false
      constraints instance_of: __MODULE__
      argument :organization_id, :uuid, allow_nil?: false
      argument :version_id, :uuid, allow_nil?: false

      argument :key, QuickTrain.Forms.PlainText,
        allow_nil?: false,
        constraints: [
          trim?: false,
          allow_empty?: true,
          match: ~r/\A[^\x00]*\z/u,
          max_length: 512,
          length_count: :bytes,
          min_length: 1
        ]

      argument :value_family, QuickTrain.Forms.InputValueFamily, allow_nil?: false

      argument :cardinality, QuickTrain.Forms.FieldCardinality,
        allow_nil?: false,
        default: :single

      argument :required, :boolean, allow_nil?: false
      argument :intended_use, QuickTrain.Forms.AssetIntendedUse
      argument :input_slot_id, :uuid, allow_nil?: false
      run {Module.concat(["QuickTrain.Forms.Authoring"]), []}
    end

    action :update_in_draft, :struct do
      allow_nil? false
      constraints instance_of: __MODULE__
      argument :organization_id, :uuid, allow_nil?: false
      argument :version_id, :uuid, allow_nil?: false
      argument :id, :uuid, allow_nil?: false

      argument :value_family, QuickTrain.Forms.InputValueFamily

      argument :cardinality, QuickTrain.Forms.FieldCardinality
      argument :required, :boolean
      argument :intended_use, QuickTrain.Forms.AssetIntendedUse
      run {Module.concat(["QuickTrain.Forms.Authoring"]), []}
    end

    action :remove_from_draft, :boolean do
      allow_nil? false
      argument :organization_id, :uuid, allow_nil?: false
      argument :version_id, :uuid, allow_nil?: false
      argument :id, :uuid, allow_nil?: false
      run {Module.concat(["QuickTrain.Forms.Authoring"]), []}
    end

    create :create_internal do
      accept [
        :key,
        :value_family,
        :cardinality,
        :required,
        :intended_use,
        :input_slot_id,
        :version_id
      ]
    end

    update :update_internal do
      accept [:value_family, :cardinality, :required, :intended_use]
    end

    destroy :destroy_internal
  end

  policies do
    policy action(:read) do
      authorize_if {QuickTrain.Forms.NestedRead, path: [:version, :form]}
    end

    policy action(:read) do
      authorize_if accessing_from(Module.concat(["QuickTrain.Forms.FormVersion"]), :requirements)

      authorize_if accessing_from(
                     Module.concat(["QuickTrain.Forms.InputSlotDefinition"]),
                     :requirements
                   )

      authorize_if accessing_from(
                     Module.concat(["QuickTrain.Forms.AnnotationConstraints"]),
                     :source_requirement
                   )

      authorize_if accessing_from(
                     Module.concat(["QuickTrain.Forms.InputSource"]),
                     :source_requirement
                   )

      authorize_if accessing_from(Module.concat(["QuickTrain.Forms.BoundValue"]), :requirement)
    end

    policy action([:list_scoped, :get_scoped]) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "forms.read"}
    end

    policy action([:add_to_draft, :update_in_draft, :remove_from_draft]) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "forms.manage"}
    end
  end

  graphql do
    type :form_input_field_requirement
    derive_filter? false
    derive_sort? false
    complexity {Module.concat(["QuickTrain.Forms"]), :connection_complexity}
    relationships []
  end

  postgres do
    table "form_input_field_requirements"
    repo QuickTrain.Repo

    references do
      reference :input_slot, on_delete: :restrict, match_with: [version_id: :version_id]
      reference :version, on_delete: :restrict
    end

    custom_indexes do
      index [:id, :version_id], unique: true
    end

    check_constraints do
      check_constraint :value_family, "form_input_field_requirements_check_0",
        check:
          "value_family IN ('text', 'integer', 'decimal', 'boolean', 'utc_datetime', 'asset')"

      check_constraint :cardinality, "form_input_field_requirements_check_1",
        check: "cardinality IN ('single')"

      check_constraint :intended_use, "form_input_field_requirements_check_2",
        check: "intended_use IN ('download', 'image')"

      check_constraint :intended_use, "form_input_field_requirements_check_3",
        check:
          "(value_family = 'asset' AND intended_use IS NOT NULL) OR (value_family <> 'asset' AND intended_use IS NULL)"
    end
  end

  identities do
    identity :parent_key, [:input_slot_id, :key]
  end
end
