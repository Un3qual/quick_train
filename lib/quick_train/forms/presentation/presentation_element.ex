defmodule QuickTrain.Forms.Presentation.PresentationElement do
  @moduledoc "Organization-scoped presentation element definition."
  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Forms,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias QuickTrain.Authorization.Checks.OrganizationCapability
  alias QuickTrain.Forms.Changes.DraftWrite
  alias QuickTrain.Forms.FormVersion

  alias QuickTrain.Forms.Presentation.{
    BoundValue,
    Heading,
    Instruction,
    QuestionPlacement,
    Section
  }

  alias QuickTrain.Forms.Types.{PlainText, PresentationKind}
  alias QuickTrain.Repo

  attributes do
    uuid_primary_key :id

    attribute :kind, PresentationKind,
      public?: true,
      allow_nil?: false

    attribute :position, :integer,
      public?: true,
      allow_nil?: false,
      constraints: [min: 0, max: 2_147_483_647]

    timestamps()
  end

  relationships do
    belongs_to :version, FormVersion, allow_nil?: false, attribute_public?: true

    has_one :instruction, Instruction,
      destination_attribute: :element_id,
      public?: true

    has_one :heading, Heading,
      destination_attribute: :element_id,
      public?: true

    has_one :section, Section,
      destination_attribute: :element_id,
      public?: true

    has_one :bound_value, BoundValue,
      destination_attribute: :element_id,
      public?: true

    has_one :question_placement, QuestionPlacement,
      destination_attribute: :element_id,
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
                 stable_sort: [position: :asc, id: :asc]
    end

    read :list_scoped do
      argument :organization_id, :uuid, allow_nil?: false
      filter expr(version.form.organization_id == ^arg(:organization_id))

      pagination keyset?: true,
                 required?: true,
                 default_limit: 50,
                 max_page_size: 100,
                 stable_sort: [position: :asc, id: :asc]
    end

    read :get_scoped do
      get? true
      argument :organization_id, :uuid, allow_nil?: false
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id) and version.form.organization_id == ^arg(:organization_id))
    end

    create :add_to_draft do
      accept [:kind, :position, :version_id]
      argument :organization_id, :uuid, allow_nil?: false
      argument :text, PlainText, constraints: [max_length: 16_384]
      argument :requirement_id, :uuid
      argument :question_id, :uuid
      argument :section_content, :map, public?: false, default: %{}

      validate present(:text), where: [attribute_in(:kind, [:instruction, :heading, :section])]
      validate present(:requirement_id), where: [attribute_equals(:kind, :bound_value)]
      validate present(:question_id), where: [attribute_equals(:kind, :question)]
      validate absent(:text), where: [attribute_in(:kind, [:bound_value, :question])]
      validate absent(:requirement_id), where: [attribute_does_not_equal(:kind, :bound_value)]
      validate absent(:question_id), where: [attribute_does_not_equal(:kind, :question)]

      change DraftWrite

      change manage_relationship(:text, :instruction,
               type: :create,
               on_no_match: {:create, :create_internal},
               value_is_key: :text,
               authorize?: false
             ),
             where: [attribute_equals(:kind, :instruction)]

      change manage_relationship(:text, :heading,
               type: :create,
               on_no_match: {:create, :create_internal},
               value_is_key: :text,
               authorize?: false
             ),
             where: [attribute_equals(:kind, :heading)]

      change set_context(%{shared: %{forms_section_text: arg(:text)}}),
        where: [attribute_equals(:kind, :section)]

      change manage_relationship(:section_content, :section,
               type: :create,
               on_no_match: {:create, :create_internal},
               authorize?: false
             ),
             where: [attribute_equals(:kind, :section)]

      change manage_relationship(:requirement_id, :bound_value,
               type: :create,
               on_no_match: {:create, :create_internal},
               value_is_key: :requirement_id,
               authorize?: false
             ),
             where: [attribute_equals(:kind, :bound_value)]

      change manage_relationship(:question_id, :question_placement,
               type: :create,
               on_no_match: {:create, :create_internal},
               value_is_key: :question_id,
               authorize?: false
             ),
             where: [attribute_equals(:kind, :question)]
    end

    update :update_in_draft do
      require_atomic? false
      atomic_upgrade_with :read_for_authoring
      accept [:position]
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
      change cascade_destroy(:instruction, action: :destroy_internal, after_action?: false)
      change cascade_destroy(:heading, action: :destroy_internal, after_action?: false)
      change cascade_destroy(:section, action: :destroy_internal, after_action?: false)
      change cascade_destroy(:bound_value, action: :destroy_internal, after_action?: false)
      change cascade_destroy(:question_placement, action: :destroy_internal, after_action?: false)
    end

    action :reorder, :boolean do
      transaction? true
      allow_nil? false
      argument :organization_id, :uuid, allow_nil?: false
      argument :version_id, :uuid, allow_nil?: false
      argument :ids, {:array, :uuid}, allow_nil?: false, constraints: [max_length: 1000]
      run {Module.concat(["QuickTrain.Forms.Authoring"]), []}
    end

    create :create_internal do
      accept [:kind, :position, :version_id]
      argument :copied_id, :uuid
      change set_attribute(:id, arg(:copied_id), set_when_nil?: false)
    end

    update :update_internal do
      accept [:position]
    end
  end

  policies do
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
      authorize_if accessing_from(Module.concat(["QuickTrain.Forms.FormVersion"]), :elements)
    end

    policy action([:list_scoped, :get_scoped]) do
      authorize_if {OrganizationCapability, capability: "forms.read"}
    end

    policy action([:add_to_draft, :update_in_draft, :remove_from_draft, :reorder]) do
      authorize_if {OrganizationCapability, capability: "forms.manage"}
    end
  end

  graphql do
    type :form_presentation_element
    derive_filter? false
    derive_sort? false
    complexity {Module.concat(["QuickTrain.Forms"]), :connection_complexity}
    relationships [:instruction, :heading, :section, :bound_value, :question_placement]
  end

  postgres do
    table "form_presentation_elements"
    repo Repo

    custom_statements do
      statement :position_unique do
        up "ALTER TABLE form_presentation_elements ADD CONSTRAINT form_presentation_elements_position_unique UNIQUE (version_id, position) DEFERRABLE INITIALLY DEFERRED;"

        down "ALTER TABLE form_presentation_elements DROP CONSTRAINT form_presentation_elements_position_unique;"
      end
    end

    references do
      reference :version, on_delete: :restrict
    end

    custom_indexes do
      index [:id, :version_id], unique: true
    end

    check_constraints do
      check_constraint :kind, "form_presentation_elements_check_0",
        check: "kind IN ('instruction', 'heading', 'section', 'bound_value', 'question')"

      check_constraint :position, "form_presentation_elements_check_1",
        check: "position BETWEEN 0 AND 2147483647"
    end
  end
end
