# ex_dna:disable-for-this-file
# Intentional typed Ash declarations; executable authoring is shared in Authoring and Graph.
defmodule QuickTrain.Forms.IntegerConstraints do
  @moduledoc "Organization-scoped integer constraints definition."
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
      constraints: [min: -2_147_483_648, max: 2_147_483_647]

    attribute :maximum, :integer,
      public?: true,
      constraints: [min: -2_147_483_648, max: 2_147_483_647]

    timestamps()
  end

  relationships do
    belongs_to :question, QuickTrain.Forms.QuestionDefinition,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :version, QuickTrain.Forms.FormVersion, allow_nil?: false, attribute_public?: true
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
      argument :minimum, :integer, constraints: [min: -2_147_483_648, max: 2_147_483_647]
      argument :maximum, :integer, constraints: [min: -2_147_483_648, max: 2_147_483_647]
      argument :question_id, :uuid, allow_nil?: false
      run {Module.concat(["QuickTrain.Forms.Authoring"]), []}
    end

    action :update_in_draft, :struct do
      allow_nil? false
      constraints instance_of: __MODULE__
      argument :organization_id, :uuid, allow_nil?: false
      argument :version_id, :uuid, allow_nil?: false
      argument :id, :uuid, allow_nil?: false
      argument :minimum, :integer, constraints: [min: -2_147_483_648, max: 2_147_483_647]
      argument :maximum, :integer, constraints: [min: -2_147_483_648, max: 2_147_483_647]
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
      accept [:minimum, :maximum, :question_id, :version_id]
    end

    update :update_internal do
      accept [:minimum, :maximum]
    end

    destroy :destroy_internal
  end

  policies do
    policy action(:read) do
      authorize_if {QuickTrain.Forms.NestedRead, path: [:version, :form]}
    end

    policy action(:read) do
      authorize_if accessing_from(
                     Module.concat(["QuickTrain.Forms.QuestionDefinition"]),
                     :integer_constraints
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
    type :form_integer_constraints
    derive_filter? false
    derive_sort? false
    complexity {Module.concat(["QuickTrain.Forms"]), :connection_complexity}
    relationships []
  end

  postgres do
    table "form_integer_constraints"
    repo QuickTrain.Repo

    references do
      reference :question, on_delete: :restrict, match_with: [version_id: :version_id]
      reference :version, on_delete: :restrict
    end

    custom_indexes do
      index [:id, :version_id], unique: true
    end

    check_constraints do
      check_constraint :minimum, "form_integer_constraints_check_0",
        check: "minimum BETWEEN -2147483648 AND 2147483647"

      check_constraint :maximum, "form_integer_constraints_check_1",
        check: "maximum BETWEEN -2147483648 AND 2147483647"

      check_constraint :minimum, "form_integer_constraints_check_2", check: "minimum <= maximum"
    end
  end

  identities do
    identity :question, [:question_id]
  end
end
