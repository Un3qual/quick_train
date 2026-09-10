# ex_dna:disable-for-this-file
# Intentional typed Ash declarations; executable authoring is shared in Authoring and Graph.
defmodule QuickTrain.Forms.Questions.QuestionOption do
  @moduledoc "Organization-scoped question option definition."
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

    attribute :label, QuickTrain.Forms.Types.PlainText,
      public?: true,
      allow_nil?: false,
      constraints: [
        max_length: 1024,
        min_length: 1
      ]

    attribute :position, :integer,
      public?: true,
      allow_nil?: false,
      constraints: [min: 0, max: 2_147_483_647]

    timestamps()
  end

  relationships do
    belongs_to :question, QuickTrain.Forms.Questions.QuestionDefinition,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :version, QuickTrain.Forms.FormVersion, allow_nil?: false, attribute_public?: true
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
      accept [:key, :label, :position, :question_id, :version_id]
      argument :organization_id, :uuid, allow_nil?: false
      change QuickTrain.Forms.Changes.DraftWrite
    end

    update :update_in_draft do
      require_atomic? false
      atomic_upgrade_with :read_for_authoring
      accept [:label, :position]
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

    action :reorder, :boolean do
      transaction? true
      allow_nil? false
      argument :organization_id, :uuid, allow_nil?: false
      argument :version_id, :uuid, allow_nil?: false
      argument :question_id, :uuid, allow_nil?: false
      argument :ids, {:array, :uuid}, allow_nil?: false, constraints: [max_length: 1000]
      run {Module.concat(["QuickTrain.Forms.Authoring"]), []}
    end

    create :create_internal do
      accept [:key, :label, :position, :question_id, :version_id]
      argument :copied_id, :uuid
      change set_attribute(:id, arg(:copied_id), set_when_nil?: false)
    end

    update :update_internal do
      accept [:label, :position]
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
      authorize_if accessing_from(
                     Module.concat(["QuickTrain.Forms.Questions.QuestionDefinition"]),
                     :options
                   )
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

  validations do
    validate match(:label, ~r/\S/u), where: [changing(:label)]
  end

  graphql do
    type :form_question_option
    derive_filter? false
    derive_sort? false
    complexity {Module.concat(["QuickTrain.Forms"]), :connection_complexity}
    relationships []
  end

  postgres do
    table "form_question_options"
    repo QuickTrain.Repo

    references do
      reference :question, on_delete: :restrict, match_with: [version_id: :version_id]
      reference :version, on_delete: :restrict
    end

    custom_indexes do
      index [:id, :version_id], unique: true
    end

    check_constraints do
      check_constraint :position, "form_question_options_check_0",
        check: "position BETWEEN 0 AND 2147483647"
    end
  end

  identities do
    identity :parent_key, [:question_id, :key]
  end
end
