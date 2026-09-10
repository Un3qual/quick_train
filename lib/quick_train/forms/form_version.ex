defmodule QuickTrain.Forms.FormVersion do
  @moduledoc "Organization-scoped form version definition."
  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Forms,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id

    attribute :version, :integer,
      public?: true,
      allow_nil?: false,
      constraints: [min: 1, max: 2_147_483_647]

    attribute :state, QuickTrain.Forms.Types.VersionState,
      public?: true,
      allow_nil?: false,
      default: :draft

    attribute :title, QuickTrain.Forms.Types.PlainText,
      public?: true,
      constraints: [
        max_length: 1024
      ]

    attribute :description, QuickTrain.Forms.Types.PlainText,
      public?: true,
      constraints: [
        max_length: 16_384
      ]

    attribute :published_at, :utc_datetime_usec, public?: true
    timestamps()
  end

  relationships do
    belongs_to :form, QuickTrain.Forms.Form, allow_nil?: false, attribute_public?: true

    has_many :input_slots, QuickTrain.Forms.Inputs.InputSlotDefinition,
      destination_attribute: :version_id,
      public?: true

    has_many :requirements, QuickTrain.Forms.Inputs.InputFieldRequirement,
      destination_attribute: :version_id,
      public?: true

    has_many :questions, QuickTrain.Forms.Questions.QuestionDefinition,
      destination_attribute: :version_id,
      public?: true

    has_many :elements, QuickTrain.Forms.Presentation.PresentationElement,
      destination_attribute: :version_id,
      public?: true

    has_many :label_sets, QuickTrain.Forms.Labels.LabelSet,
      destination_attribute: :version_id,
      public?: true
  end

  actions do
    read :lock_for_authoring do
      get? true
      argument :id, :uuid, allow_nil?: false
      argument :organization_id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id) and form.organization_id == ^arg(:organization_id))
      prepare build(lock: :for_update)
    end

    read :read_for_authoring do
      pagination keyset?: true, required?: false
    end

    read :read do
      primary? true

      pagination keyset?: true,
                 required?: false,
                 default_limit: 50,
                 max_page_size: 100,
                 stable_sort: [version: :asc, id: :asc]
    end

    read :list_scoped do
      argument :organization_id, :uuid, allow_nil?: false
      filter expr(form.organization_id == ^arg(:organization_id))

      pagination keyset?: true,
                 required?: true,
                 default_limit: 50,
                 max_page_size: 100,
                 stable_sort: [version: :asc, id: :asc]
    end

    read :get_scoped do
      get? true
      argument :organization_id, :uuid, allow_nil?: false
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id) and form.organization_id == ^arg(:organization_id))
    end

    create :create_draft do
      accept [:title, :description, :form_id]
      argument :organization_id, :uuid, allow_nil?: false
      change QuickTrain.Forms.Changes.AllocateVersion
    end

    action :copy_published, :struct do
      transaction? true
      allow_nil? false
      constraints instance_of: __MODULE__
      argument :organization_id, :uuid, allow_nil?: false
      argument :form_id, :uuid, allow_nil?: false
      argument :source_version_id, :uuid, allow_nil?: false
      run {Module.concat(["QuickTrain.Forms.Authoring"]), []}
    end

    update :update_draft do
      require_atomic? false
      atomic_upgrade_with :read_for_authoring
      accept [:title, :description]
      argument :organization_id, :uuid, allow_nil?: false
      change QuickTrain.Forms.Changes.DraftWrite
    end

    action :publish, :struct do
      transaction? true
      allow_nil? false
      constraints instance_of: __MODULE__
      argument :organization_id, :uuid, allow_nil?: false
      argument :version_id, :uuid, allow_nil?: false
      run {Module.concat(["QuickTrain.Forms.Authoring"]), []}
    end

    create :create_internal do
      accept [:version, :title, :description, :form_id]
    end

    update :update_internal do
      accept [:title, :description]
    end

    update :publish_internal do
      accept []
      change set_attribute(:state, :published)
      change atomic_update(:published_at, expr(now()))
    end
  end

  policies do
    policy action(:read_for_authoring) do
      authorize_if context_equals(:query_for, :bulk_update)
      authorize_if context_equals(:query_for, :bulk_destroy)
    end

    policy action(:read_for_authoring) do
      authorize_if {QuickTrain.Forms.NestedRead, path: [:form], capabilities: ["forms.manage"]}
    end

    policy action(:read) do
      authorize_if {QuickTrain.Forms.NestedRead, path: [:form]}
    end

    policy action(:read) do
      authorize_if accessing_from(Module.concat(["QuickTrain.Forms.Form"]), :versions)
    end

    policy action([:list_scoped, :get_scoped]) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "forms.read"}
    end

    policy action([:create_draft, :copy_published, :update_draft, :publish]) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "forms.manage"}
    end
  end

  graphql do
    type :form_version
    derive_filter? false
    derive_sort? false
    complexity {Module.concat(["QuickTrain.Forms"]), :connection_complexity}
    relationships [:input_slots, :requirements, :questions, :elements, :label_sets]

    paginate_relationship_with input_slots: :relay,
                               requirements: :relay,
                               questions: :relay,
                               elements: :relay,
                               label_sets: :relay
  end

  postgres do
    table "form_versions"
    repo QuickTrain.Repo

    references do
      reference :form, on_delete: :restrict
    end

    check_constraints do
      check_constraint :version, "form_versions_check_0",
        check: "version BETWEEN 1 AND 2147483647"

      check_constraint :state, "form_versions_check_1", check: "state IN ('draft', 'published')"

      check_constraint :state, "form_versions_check_2",
        check:
          "(state = 'draft' AND published_at IS NULL) OR (state = 'published' AND published_at IS NOT NULL)"
    end
  end

  identities do
    identity :form_version, [:form_id, :version]
  end
end
