# ex_dna:disable-for-this-file
# Intentional typed Ash declarations; executable authoring is shared in Authoring and Graph.
defmodule QuickTrain.Forms.Questions.Constraints.TextConstraints do
  @moduledoc "Organization-scoped text constraints definition."
  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Forms,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias QuickTrain.Authorization.Checks.OrganizationCapability
  alias QuickTrain.Forms.Changes.DraftWrite
  alias QuickTrain.Forms.FormVersion
  alias QuickTrain.Forms.Questions.QuestionDefinition
  alias QuickTrain.Repo

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :minimum, :integer, public?: true, constraints: [min: 0, max: 2_147_483_647]
    attribute :maximum, :integer, public?: true, constraints: [min: 0, max: 2_147_483_647]
    timestamps()
  end

  relationships do
    belongs_to :question, QuestionDefinition,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :version, FormVersion, allow_nil?: false, attribute_public?: true
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
      accept [:minimum, :maximum, :question_id, :version_id]
      argument :organization_id, :uuid, allow_nil?: false
      change DraftWrite
    end

    update :update_in_draft do
      require_atomic? false
      atomic_upgrade_with :read_for_authoring
      accept [:minimum, :maximum]
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
      accept [:id, :minimum, :maximum, :question_id, :version_id]
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
                     :text_constraints
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
    validate compare(:minimum, less_than_or_equal_to: :maximum),
      where: [present([:minimum, :maximum])],
      before_action?: true,
      only_when_valid?: true
  end

  graphql do
    type :form_text_constraints
    derive_filter? false
    derive_sort? false
    complexity {Module.concat(["QuickTrain.Forms"]), :connection_complexity}
    relationships []
  end

  postgres do
    table "form_text_constraints"
    repo Repo

    references do
      reference :question, on_delete: :restrict, match_with: [version_id: :version_id]
      reference :version, on_delete: :restrict, index?: true
    end

    check_constraints do
      check_constraint :minimum, "form_text_constraints_check_0",
        check: "minimum BETWEEN 0 AND 2147483647"

      check_constraint :maximum, "form_text_constraints_check_1",
        check: "maximum BETWEEN 0 AND 2147483647"

      check_constraint :minimum, "form_text_constraints_check_2", check: "minimum <= maximum"
    end
  end

  identities do
    identity :question, [:question_id]
  end
end
