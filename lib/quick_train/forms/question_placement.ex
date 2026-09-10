# ex_dna:disable-for-this-file
# Intentional typed Ash declarations; executable authoring is shared in Authoring and Graph.
defmodule QuickTrain.Forms.QuestionPlacement do
  @moduledoc "Organization-scoped question placement definition."
  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Forms,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id
    timestamps()
  end

  relationships do
    belongs_to :element, QuickTrain.Forms.PresentationElement,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :question, QuickTrain.Forms.QuestionDefinition,
      public?: true,
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

    action :update_in_draft, :struct do
      allow_nil? false
      constraints instance_of: __MODULE__
      argument :organization_id, :uuid, allow_nil?: false
      argument :version_id, :uuid, allow_nil?: false
      argument :id, :uuid, allow_nil?: false
      argument :question_id, :uuid
      run {Module.concat(["QuickTrain.Forms.Authoring"]), []}
    end

    create :create_internal do
      accept [:element_id, :question_id, :version_id]
    end

    update :update_internal do
      accept [:question_id]
    end

    destroy :destroy_internal
  end

  policies do
    policy action(:read) do
      authorize_if {QuickTrain.Forms.NestedRead, path: [:version, :form]}
    end

    policy action(:read) do
      authorize_if accessing_from(
                     Module.concat(["QuickTrain.Forms.PresentationElement"]),
                     :question_placement
                   )
    end

    policy action([:list_scoped, :get_scoped]) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "forms.read"}
    end

    policy action([:update_in_draft]) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "forms.manage"}
    end
  end

  graphql do
    type :form_question_placement
    derive_filter? false
    derive_sort? false
    complexity {Module.concat(["QuickTrain.Forms"]), :connection_complexity}
    relationships [:question]
  end

  postgres do
    table "form_question_placements"
    repo QuickTrain.Repo

    references do
      reference :element, on_delete: :restrict, match_with: [version_id: :version_id]
      reference :question, on_delete: :restrict, match_with: [version_id: :version_id]
      reference :version, on_delete: :restrict
    end

    custom_indexes do
      index [:id, :version_id], unique: true
    end
  end

  identities do
    identity :element, [:element_id]
  end
end
