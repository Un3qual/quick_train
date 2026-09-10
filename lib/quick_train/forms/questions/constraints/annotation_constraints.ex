defmodule QuickTrain.Forms.Questions.Constraints.AnnotationConstraints do
  @moduledoc "Organization-scoped annotation constraints definition."
  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Forms,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id

    attribute :minimum, :integer,
      public?: true,
      allow_nil?: false,
      constraints: [min: 0, max: 2_147_483_647]

    attribute :maximum, :integer,
      public?: true,
      allow_nil?: false,
      constraints: [min: 0, max: 2_147_483_647]

    timestamps()
  end

  relationships do
    belongs_to :question, QuickTrain.Forms.Questions.QuestionDefinition,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :source_requirement, QuickTrain.Forms.Inputs.InputFieldRequirement,
      public?: true,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :label_set, QuickTrain.Forms.Labels.LabelSet,
      public?: true,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :version, QuickTrain.Forms.FormVersion, allow_nil?: false, attribute_public?: true
  end

  calculations do
    calculate :source_convention,
              :string,
              expr(
                cond do
                  question.family == :text_spans ->
                    "unicode_codepoints_zero_based_end_exclusive"

                  question.family == :raster_masks ->
                    "immutable_mask_asset_with_source_dimensions"

                  true ->
                    "normalized_image_coordinates"
                end
              ),
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
      accept [
        :minimum,
        :maximum,
        :question_id,
        :source_requirement_id,
        :label_set_id,
        :version_id
      ]

      argument :organization_id, :uuid, allow_nil?: false
      change QuickTrain.Forms.Changes.DraftWrite
    end

    update :update_in_draft do
      require_atomic? false
      atomic_upgrade_with :read_for_authoring
      accept [:minimum, :maximum, :source_requirement_id, :label_set_id]
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
      accept [
        :minimum,
        :maximum,
        :question_id,
        :source_requirement_id,
        :label_set_id,
        :version_id
      ]
    end

    create :copy_internal do
      accept [
        :minimum,
        :maximum,
        :question_id,
        :source_requirement_id,
        :label_set_id,
        :version_id
      ]

      argument :copied_id, :uuid, allow_nil?: false
      change set_attribute(:id, arg(:copied_id))
    end

    update :update_internal do
      accept [:minimum, :maximum, :source_requirement_id, :label_set_id]
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
      authorize_if accessing_from(
                     Module.concat(["QuickTrain.Forms.Questions.QuestionDefinition"]),
                     :annotation_constraints
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
    type :form_annotation_constraints
    derive_filter? false
    derive_sort? false
    complexity {Module.concat(["QuickTrain.Forms"]), :connection_complexity}
    relationships [:source_requirement, :label_set]
  end

  postgres do
    table "form_annotation_constraints"
    repo QuickTrain.Repo

    references do
      reference :question, on_delete: :restrict, match_with: [version_id: :version_id]
      reference :source_requirement, on_delete: :restrict, match_with: [version_id: :version_id]
      reference :label_set, on_delete: :restrict, match_with: [version_id: :version_id]
      reference :version, on_delete: :restrict
    end

    custom_indexes do
      index [:id, :version_id], unique: true
    end

    check_constraints do
      check_constraint :minimum, "form_annotation_constraints_check_0",
        check: "minimum BETWEEN 0 AND 2147483647"

      check_constraint :maximum, "form_annotation_constraints_check_1",
        check: "maximum BETWEEN 0 AND 2147483647"

      check_constraint :minimum, "form_annotation_constraints_check_2",
        check: "minimum <= maximum"
    end
  end

  identities do
    identity :question, [:question_id]
  end
end
