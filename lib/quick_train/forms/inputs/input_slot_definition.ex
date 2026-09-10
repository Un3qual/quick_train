defmodule QuickTrain.Forms.Inputs.InputSlotDefinition do
  @moduledoc "Organization-scoped input slot definition definition."
  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Forms,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id

    attribute :key, QuickTrain.Forms.Types.PlainText,
      public?: true,
      allow_nil?: false,
      constraints: [
        max_length: 512,
        min_length: 1
      ]

    attribute :minimum, :integer,
      public?: true,
      allow_nil?: false,
      constraints: [min: 1, max: 100]

    attribute :maximum, :integer,
      public?: true,
      allow_nil?: false,
      constraints: [min: 1, max: 100]

    timestamps()
  end

  relationships do
    belongs_to :version, QuickTrain.Forms.FormVersion, allow_nil?: false, attribute_public?: true

    has_many :requirements, QuickTrain.Forms.Inputs.InputFieldRequirement,
      destination_attribute: :input_slot_id,
      public?: true
  end

  actions do
    read :read_for_authoring do
      pagination keyset?: true, required?: false
    end

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

    create :add_to_draft do
      accept [:key, :minimum, :maximum, :version_id]
      argument :organization_id, :uuid, allow_nil?: false
      change QuickTrain.Forms.Changes.DraftWrite
    end

    update :update_in_draft do
      require_atomic? false
      atomic_upgrade_with :read_for_authoring
      accept [:minimum, :maximum]
      argument :organization_id, :uuid, allow_nil?: false
      argument :version_id, :uuid, allow_nil?: false
      change QuickTrain.Forms.Changes.DraftWrite
    end

    destroy :remove_from_draft do
      require_atomic? false
      atomic_upgrade_with :read_for_authoring
      argument :organization_id, :uuid, allow_nil?: false
      argument :version_id, :uuid, allow_nil?: false
      change QuickTrain.Forms.Changes.DraftWrite
    end

    create :create_internal do
      accept [:key, :minimum, :maximum, :version_id]
    end

    create :copy_internal do
      accept [:key, :minimum, :maximum, :version_id]
      argument :copied_id, :uuid, allow_nil?: false
      change set_attribute(:id, arg(:copied_id))
    end

    update :update_internal do
      accept [:minimum, :maximum]
    end

    destroy :destroy_internal
  end

  policies do
    policy action(:read_for_authoring) do
      authorize_if context_equals(:query_for, :bulk_update)
      authorize_if context_equals(:query_for, :bulk_destroy)
    end

    policy action(:read_for_authoring) do
      authorize_if {QuickTrain.Forms.NestedRead,
                    path: [:version, :form], capabilities: ["forms.manage"]}
    end

    policy action(:read) do
      authorize_if {QuickTrain.Forms.NestedRead, path: [:version, :form]}
    end

    policy action(:read) do
      authorize_if accessing_from(Module.concat(["QuickTrain.Forms.FormVersion"]), :input_slots)

      authorize_if accessing_from(
                     Module.concat(["QuickTrain.Forms.Questions.InputSource"]),
                     :input_slot
                   )
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
    type :form_input_slot_definition
    derive_filter? false
    derive_sort? false
    complexity {Module.concat(["QuickTrain.Forms"]), :connection_complexity}
    relationships [:requirements]
    paginate_relationship_with requirements: :relay
  end

  postgres do
    table "form_input_slot_definitions"
    repo QuickTrain.Repo

    references do
      reference :version, on_delete: :restrict
    end

    custom_indexes do
      index [:id, :version_id], unique: true
    end

    check_constraints do
      check_constraint :minimum, "form_input_slot_definitions_check_0",
        check: "minimum BETWEEN 1 AND 100"

      check_constraint :maximum, "form_input_slot_definitions_check_1",
        check: "maximum BETWEEN 1 AND 100"

      check_constraint :minimum, "form_input_slot_definitions_check_2",
        check: "minimum <= maximum"
    end
  end

  identities do
    identity :parent_key, [:version_id, :key]
  end
end
