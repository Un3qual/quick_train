# ex_dna:disable-for-this-file
# Intentional typed Ash declarations; executable authoring is shared in Authoring and Graph.
defmodule QuickTrain.Forms.Questions.Constraints.SelectionConstraints do
  @moduledoc "Organization-scoped selection constraints definition."
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
  alias QuickTrain.Forms.Questions.QuestionDefinition
  alias QuickTrain.Repo

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      generated?: true,
      public?: true,
      writable?: false

    attribute :minimum, :integer,
      public?: true,
      allow_nil?: false,
      constraints: [min: 1, max: 200]

    attribute :maximum, :integer,
      public?: true,
      allow_nil?: false,
      constraints: [min: 1, max: 200]

    timestamps()
  end

  relationships do
    belongs_to :question, QuestionDefinition,
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
      prepare QuickTrain.Tasks.ContractAccess.DefinitionRead
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
      accept [:minimum, :maximum, :question_id, :version_id]
    end
  end

  policies do
    bypass action(:read) do
      authorize_if QuickTrain.Tasks.ContractAccess
    end

    policy action(:get_task_definition) do
      authorize_if QuickTrain.Tasks.ContractAccess
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
      authorize_if accessing_from(
                     Module.concat(["QuickTrain.Forms.Questions.QuestionDefinition"]),
                     :selection_constraints
                   )
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
    type :form_selection_constraints
    derive_filter? false
    derive_sort? false
    relationships []
  end

  postgres do
    migration_defaults id: "fragment(\"gen_random_uuid()\")"
    table "form_selection_constraints"
    repo Repo

    references do
      reference :question, on_delete: :restrict, match_with: [version_id: :version_id]
      reference :version, on_delete: :restrict, index?: true
    end

    check_constraints do
      check_constraint :minimum, "form_selection_constraints_check_0",
        check: "minimum BETWEEN 1 AND 200"

      check_constraint :maximum, "form_selection_constraints_check_1",
        check: "maximum BETWEEN 1 AND 200"

      check_constraint :minimum, "form_selection_constraints_check_2", check: "minimum <= maximum"
    end
  end

  identities do
    identity :question, [:question_id]
  end
end
