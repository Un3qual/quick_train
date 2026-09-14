defmodule QuickTrain.Forms.Inputs.InputFieldRequirement do
  @moduledoc "Organization-scoped input field requirement definition."
  use Ash.Resource,
    primary_read_warning?: false,
    otp_app: :quick_train,
    domain: QuickTrain.Forms,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias QuickTrain.Authorization.Checks.OrganizationCapability
  alias QuickTrain.Forms.Changes.DraftWrite
  alias QuickTrain.Forms.FormVersion
  alias QuickTrain.Forms.Inputs.InputSlotDefinition
  alias QuickTrain.Forms.Types.{AssetIntendedUse, FieldCardinality, InputValueFamily}
  alias QuickTrain.Repo

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      generated?: true,
      public?: true,
      writable?: false

    attribute :key, :string,
      public?: true,
      allow_nil?: false,
      constraints: [
        trim?: false,
        allow_empty?: true,
        length_count: :bytes,
        max_length: 512,
        min_length: 1
      ]

    attribute :value_family, InputValueFamily,
      public?: true,
      allow_nil?: false

    attribute :cardinality, FieldCardinality,
      public?: true,
      allow_nil?: false,
      default: :single

    attribute :required, :boolean, public?: true, allow_nil?: false
    attribute :intended_use, AssetIntendedUse, public?: true
    timestamps()
  end

  relationships do
    belongs_to :input_slot, InputSlotDefinition,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :version, FormVersion, allow_nil?: false, attribute_public?: true
  end

  actions do
    read :get_task_definition do
      get? true
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      argument :id, :uuid, allow_nil?: false
      argument :attempt_id, :uuid
      filter expr(id == ^arg(:id))
      prepare Module.concat(["QuickTrain.Tasks.ContractAccess.DefinitionRead"])
    end

    read :read_for_authoring do
      pagination keyset?: true, required?: false
    end

    read :read do
      primary? true

      prepare build(sort: [inserted_at: :asc, id: :asc])

      pagination keyset?: true,
                 required?: false,
                 default_limit: 50,
                 max_page_size: 100,
                 stable_sort: [inserted_at: :asc, id: :asc]
    end

    read :list_scoped do
      argument :organization_id, :uuid, allow_nil?: false
      filter expr(version.form.organization_id == ^arg(:organization_id))

      prepare build(sort: [inserted_at: :asc, id: :asc])

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

    create :add_to_draft do
      accept [
        :key,
        :value_family,
        :cardinality,
        :required,
        :intended_use,
        :input_slot_id,
        :version_id
      ]

      argument :organization_id, :uuid, allow_nil?: false
      change DraftWrite
    end

    update :update_in_draft do
      require_atomic? false
      atomic_upgrade_with :read_for_authoring
      accept [:value_family, :cardinality, :required, :intended_use]
      argument :organization_id, :uuid, allow_nil?: false
      argument :version_id, :uuid, allow_nil?: false
      change DraftWrite
    end

    destroy :remove_from_draft do
      require_atomic? false
      atomic_upgrade_with :read_for_authoring
      argument :organization_id, :uuid, allow_nil?: false
      argument :version_id, :uuid, allow_nil?: false
      change DraftWrite
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
  end

  policies do
    bypass action(:read) do
      authorize_if Module.concat(["QuickTrain.Tasks.ContractAccess"])
    end

    policy action(:get_task_definition) do
      authorize_if Module.concat(["QuickTrain.Tasks.ContractAccess"])
    end

    policy action(:read_for_authoring) do
      authorize_if context_equals(:query_for, :bulk_update)
      authorize_if context_equals(:query_for, :bulk_destroy)
    end

    policy action(:read_for_authoring) do
      forbid_unless actor_attribute_equals(:status, "active")
      authorize_if relates_to_actor_via([:version, :form, :manager_role_assignments, :user])
    end

    policy action(:read) do
      forbid_unless actor_attribute_equals(:status, "active")
      authorize_if relates_to_actor_via([:version, :form, :reader_role_assignments, :user])
    end

    policy action(:read) do
      authorize_if accessing_from(Module.concat(["QuickTrain.Forms.FormVersion"]), :requirements)

      authorize_if accessing_from(
                     Module.concat(["QuickTrain.Forms.Inputs.InputSlotDefinition"]),
                     :requirements
                   )

      authorize_if accessing_from(
                     Module.concat([
                       "QuickTrain.Forms.Questions.Constraints.AnnotationConstraints"
                     ]),
                     :source_requirement
                   )

      authorize_if accessing_from(
                     Module.concat(["QuickTrain.Forms.Questions.QuestionDefinition"]),
                     :source_requirement
                   )

      authorize_if accessing_from(
                     Module.concat(["QuickTrain.Forms.Presentation.PresentationElement"]),
                     :requirement
                   )
    end

    policy action([:list_scoped, :get_scoped]) do
      authorize_if {OrganizationCapability, capability: "forms.read"}
    end

    policy action([:add_to_draft, :update_in_draft, :remove_from_draft]) do
      authorize_if {OrganizationCapability, capability: "forms.manage"}
    end
  end

  validations do
    validate present(:intended_use),
      where: [attribute_equals(:value_family, :asset)],
      before_action?: true,
      only_when_valid?: true

    validate absent(:intended_use),
      where: [attribute_does_not_equal(:value_family, :asset)],
      before_action?: true,
      only_when_valid?: true
  end

  graphql do
    type :form_input_field_requirement
    derive_filter? false
    derive_sort? false
    relationships []
  end

  postgres do
    migration_defaults id: "fragment(\"gen_random_uuid()\")"
    table "form_input_field_requirements"
    repo Repo

    references do
      reference :input_slot, on_delete: :restrict, match_with: [version_id: :version_id]
      reference :version, on_delete: :restrict, index?: true
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
