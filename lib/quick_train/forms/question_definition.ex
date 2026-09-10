defmodule QuickTrain.Forms.QuestionDefinition do
  @moduledoc "Organization-scoped question definition definition."
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

    attribute :prompt, QuickTrain.Forms.PlainText,
      public?: true,
      allow_nil?: false,
      constraints: [
        trim?: false,
        allow_empty?: true,
        match: ~r/\A[^\x00]*\z/u,
        max_length: 16_384,
        length_count: :bytes,
        min_length: 1
      ]

    attribute :family, QuickTrain.Forms.AnswerFamily,
      public?: true,
      allow_nil?: false

    attribute :renderer, QuickTrain.Forms.Renderer,
      public?: true,
      allow_nil?: false

    timestamps()
  end

  relationships do
    belongs_to :version, QuickTrain.Forms.FormVersion, allow_nil?: false, attribute_public?: true

    has_one :text_constraints, QuickTrain.Forms.TextConstraints,
      destination_attribute: :question_id,
      public?: true

    has_one :integer_constraints, QuickTrain.Forms.IntegerConstraints,
      destination_attribute: :question_id,
      public?: true

    has_one :decimal_constraints, QuickTrain.Forms.DecimalConstraints,
      destination_attribute: :question_id,
      public?: true

    has_one :selection_constraints, QuickTrain.Forms.SelectionConstraints,
      destination_attribute: :question_id,
      public?: true

    has_one :annotation_constraints, QuickTrain.Forms.AnnotationConstraints,
      destination_attribute: :question_id,
      public?: true

    has_one :input_source, QuickTrain.Forms.InputSource,
      destination_attribute: :question_id,
      public?: true

    has_many :options, QuickTrain.Forms.QuestionOption,
      destination_attribute: :question_id,
      public?: true
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

      argument :prompt, QuickTrain.Forms.PlainText,
        allow_nil?: false,
        constraints: [
          trim?: false,
          allow_empty?: true,
          match: ~r/\A[^\x00]*\z/u,
          max_length: 16_384,
          length_count: :bytes,
          min_length: 1
        ]

      argument :family, QuickTrain.Forms.AnswerFamily, allow_nil?: false

      argument :renderer, QuickTrain.Forms.Renderer, allow_nil?: false

      run {Module.concat(["QuickTrain.Forms.Authoring"]), []}
    end

    action :update_in_draft, :struct do
      allow_nil? false
      constraints instance_of: __MODULE__
      argument :organization_id, :uuid, allow_nil?: false
      argument :version_id, :uuid, allow_nil?: false
      argument :id, :uuid, allow_nil?: false

      argument :prompt, QuickTrain.Forms.PlainText,
        constraints: [
          trim?: false,
          allow_empty?: true,
          match: ~r/\A[^\x00]*\z/u,
          max_length: 16_384,
          length_count: :bytes,
          min_length: 1
        ]

      argument :family, QuickTrain.Forms.AnswerFamily

      argument :renderer, QuickTrain.Forms.Renderer

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
      accept [:key, :prompt, :family, :renderer, :version_id]
    end

    update :update_internal do
      accept [:prompt, :family, :renderer]
    end

    destroy :destroy_internal
  end

  policies do
    policy action(:read) do
      authorize_if {QuickTrain.Forms.NestedRead, path: [:version, :form]}
    end

    policy action(:read) do
      authorize_if accessing_from(Module.concat(["QuickTrain.Forms.FormVersion"]), :questions)

      authorize_if accessing_from(
                     Module.concat(["QuickTrain.Forms.QuestionPlacement"]),
                     :question
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

  validations do
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
    repo QuickTrain.Repo

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
