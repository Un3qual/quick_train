defmodule QuickTrain.Forms.Questions.QuestionDefinition do
  @moduledoc "Organization-scoped question definition."
  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Forms,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias QuickTrain.Authorization.Checks.OrganizationCapability
  alias QuickTrain.Forms.Changes.DraftWrite
  alias QuickTrain.Forms.FormVersion

  alias QuickTrain.Forms.Questions.Constraints.{
    AnnotationConstraints,
    DecimalConstraints,
    IntegerConstraints,
    SelectionConstraints,
    TextConstraints
  }

  alias QuickTrain.Forms.Questions.{InputSource, QuestionOption}
  alias QuickTrain.Forms.Types.{AnswerFamily, PlainText, Renderer}
  alias QuickTrain.Repo

  attributes do
    uuid_primary_key :id, writable?: true

    attribute :key, PlainText,
      public?: true,
      allow_nil?: false,
      constraints: [
        max_length: 512,
        min_length: 1
      ]

    attribute :prompt, PlainText,
      public?: true,
      allow_nil?: false,
      constraints: [
        max_length: 16_384,
        min_length: 1
      ]

    attribute :family, AnswerFamily,
      public?: true,
      allow_nil?: false

    attribute :renderer, Renderer,
      public?: true,
      allow_nil?: false

    timestamps()
  end

  relationships do
    belongs_to :version, FormVersion, allow_nil?: false, attribute_public?: true

    has_one :text_constraints, TextConstraints,
      destination_attribute: :question_id,
      public?: true

    has_one :integer_constraints, IntegerConstraints,
      destination_attribute: :question_id,
      public?: true

    has_one :decimal_constraints, DecimalConstraints,
      destination_attribute: :question_id,
      public?: true

    has_one :selection_constraints, SelectionConstraints,
      destination_attribute: :question_id,
      public?: true

    has_one :annotation_constraints, AnnotationConstraints,
      destination_attribute: :question_id,
      public?: true

    has_one :input_source, InputSource,
      destination_attribute: :question_id,
      public?: true

    has_many :options, QuestionOption,
      destination_attribute: :question_id,
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
      accept [:key, :prompt, :family, :renderer, :version_id]
      argument :organization_id, :uuid, allow_nil?: false
      change DraftWrite
    end

    update :update_in_draft do
      require_atomic? false
      atomic_upgrade_with :read_for_authoring
      accept [:prompt, :family, :renderer]
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
      accept [:id, :key, :prompt, :family, :renderer, :version_id]
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
      authorize_if accessing_from(Module.concat(["QuickTrain.Forms.FormVersion"]), :questions)

      authorize_if accessing_from(
                     Module.concat(["QuickTrain.Forms.Presentation.QuestionPlacement"]),
                     :question
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
    validate match(:key, ~r/\S/u), where: [changing(:key)]
    validate match(:prompt, ~r/\S/u), where: [changing(:prompt)]
  end

  graphql do
    type :form_question_definition
    derive_filter? false
    derive_sort? false
    complexity {Module.concat(["QuickTrain.Forms"]), :connection_complexity}

    relationships [
      :text_constraints,
      :integer_constraints,
      :decimal_constraints,
      :selection_constraints,
      :annotation_constraints,
      :input_source,
      :options
    ]

    paginate_relationship_with options: :relay
  end

  postgres do
    table "form_question_definitions"
    repo Repo

    references do
      reference :version, on_delete: :restrict
    end

    custom_indexes do
      index [:id, :version_id], unique: true
    end

    check_constraints do
      check_constraint :family, "form_question_definitions_check_0",
        check:
          "family IN ('text', 'integer', 'decimal', 'boolean', 'static_single_choice', 'static_multiple_choice', 'task_input_single_choice', 'task_input_multiple_choice', 'task_input_ranking', 'bounding_boxes', 'polygon_regions', 'raster_masks', 'text_spans')"

      check_constraint :renderer, "form_question_definitions_check_1",
        check:
          "renderer IN ('text_input', 'text_area', 'integer_input', 'stars', 'likert', 'decimal_input', 'checkbox', 'toggle', 'radio', 'dropdown', 'checkbox_group', 'pairwise', 'image_choice', 'ranking', 'bounding_boxes', 'polygon_regions', 'raster_masks', 'text_spans')"
    end
  end

  identities do
    identity :parent_key, [:version_id, :key]
  end
end
