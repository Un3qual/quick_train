defmodule QuickTrain.Forms.PresentationElement do
  @moduledoc "Organization-scoped presentation element definition."
  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Forms,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id

    attribute :kind, QuickTrain.Forms.PresentationKind,
      public?: true,
      allow_nil?: false

    attribute :position, :integer,
      public?: true,
      allow_nil?: false,
      constraints: [min: 0, max: 2_147_483_647]

    timestamps()
  end

  relationships do
    belongs_to :version, QuickTrain.Forms.FormVersion, allow_nil?: false, attribute_public?: true

    has_one :instruction, QuickTrain.Forms.Instruction,
      destination_attribute: :element_id,
      public?: true

    has_one :heading, QuickTrain.Forms.Heading, destination_attribute: :element_id, public?: true
    has_one :section, QuickTrain.Forms.Section, destination_attribute: :element_id, public?: true

    has_one :bound_value, QuickTrain.Forms.BoundValue,
      destination_attribute: :element_id,
      public?: true

    has_one :question_placement, QuickTrain.Forms.QuestionPlacement,
      destination_attribute: :element_id,
      public?: true
  end

  actions do
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

    action :add_to_draft, :struct do
      allow_nil? false
      constraints instance_of: __MODULE__
      argument :organization_id, :uuid, allow_nil?: false
      argument :version_id, :uuid, allow_nil?: false

      argument :kind, QuickTrain.Forms.PresentationKind, allow_nil?: false

      argument :position, :integer, allow_nil?: false, constraints: [min: 0, max: 2_147_483_647]

      argument :text, QuickTrain.Forms.PlainText,
        constraints: [
          trim?: false,
          allow_empty?: true,
          match: ~r/\A[^\x00]*\z/u,
          max_length: 16_384,
          length_count: :bytes
        ]

      argument :requirement_id, :uuid
      argument :question_id, :uuid
      run {Module.concat(["QuickTrain.Forms.Authoring"]), []}
    end

    action :update_in_draft, :struct do
      allow_nil? false
      constraints instance_of: __MODULE__
      argument :organization_id, :uuid, allow_nil?: false
      argument :version_id, :uuid, allow_nil?: false
      argument :id, :uuid, allow_nil?: false
      argument :position, :integer, constraints: [min: 0, max: 2_147_483_647]
      run {Module.concat(["QuickTrain.Forms.Authoring"]), []}
    end

    action :remove_from_draft, :boolean do
      allow_nil? false
      argument :organization_id, :uuid, allow_nil?: false
      argument :version_id, :uuid, allow_nil?: false
      argument :id, :uuid, allow_nil?: false
      run {Module.concat(["QuickTrain.Forms.Authoring"]), []}
    end

    action :reorder, :boolean do
      allow_nil? false
      argument :organization_id, :uuid, allow_nil?: false
      argument :version_id, :uuid, allow_nil?: false
      argument :ids, {:array, :uuid}, allow_nil?: false, constraints: [max_length: 1000]
      run {Module.concat(["QuickTrain.Forms.Authoring"]), []}
    end

    create :create_internal do
      accept [:kind, :position, :version_id]
    end

    update :update_internal do
      accept [:position]
    end

    destroy :destroy_internal
  end

  policies do
    policy action(:read) do
      authorize_if {QuickTrain.Forms.NestedRead, path: [:version, :form]}
    end

    policy action(:read) do
      authorize_if accessing_from(Module.concat(["QuickTrain.Forms.FormVersion"]), :elements)
    end

    policy action([:list_scoped, :get_scoped]) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "forms.read"}
    end

    policy action([:add_to_draft, :update_in_draft, :remove_from_draft, :reorder]) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "forms.manage"}
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
    repo QuickTrain.Repo

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
