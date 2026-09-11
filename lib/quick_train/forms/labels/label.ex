# ex_dna:disable-for-this-file
# Intentional typed Ash declarations; executable authoring is shared in Authoring and Graph.
defmodule QuickTrain.Forms.Labels.Label do
  @moduledoc "Organization-scoped label definition."
  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Forms,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias QuickTrain.Authorization.Checks.OrganizationCapability
  alias QuickTrain.Forms.Changes.DraftWrite
  alias QuickTrain.Forms.FormVersion
  alias QuickTrain.Forms.Labels.LabelSet
  alias QuickTrain.Forms.Types.PlainText
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

    attribute :text, PlainText,
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
    belongs_to :label_set, LabelSet,
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
      accept [:key, :text, :position, :label_set_id, :version_id]
      argument :organization_id, :uuid, allow_nil?: false
      change DraftWrite
    end

    update :update_in_draft do
      require_atomic? false
      atomic_upgrade_with :read_for_authoring
      accept [:text, :position]
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

    action :reorder, :boolean do
      transaction? true
      allow_nil? false
      argument :organization_id, :uuid, allow_nil?: false
      argument :version_id, :uuid, allow_nil?: false
      argument :label_set_id, :uuid, allow_nil?: false
      argument :ids, {:array, :uuid}, allow_nil?: false, constraints: [max_length: 1000]
      run {Module.concat(["QuickTrain.Forms.Authoring"]), []}
    end

    create :create_internal do
      accept [:id, :key, :text, :position, :label_set_id, :version_id]
    end

    update :update_internal do
      accept [:text, :position]
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
      authorize_if accessing_from(Module.concat(["QuickTrain.Forms.Labels.LabelSet"]), :labels)
    end

    policy action([:list_scoped, :get_scoped]) do
      authorize_if {OrganizationCapability, capability: "forms.read"}
    end

    policy action([:add_to_draft, :update_in_draft, :remove_from_draft, :reorder]) do
      authorize_if {OrganizationCapability, capability: "forms.manage"}
    end
  end

  validations do
    validate match(:text, ~r/\S/u), where: [changing(:text)]
  end

  graphql do
    type :form_label
    derive_filter? false
    derive_sort? false
    complexity {Module.concat(["QuickTrain.Forms"]), :connection_complexity}
    relationships []
  end

  postgres do
    table "form_labels"
    repo Repo

    custom_statements do
      statement :position_unique do
        up "ALTER TABLE form_labels ADD CONSTRAINT form_labels_position_unique UNIQUE (label_set_id, position) DEFERRABLE INITIALLY DEFERRED;"
        down "ALTER TABLE form_labels DROP CONSTRAINT form_labels_position_unique;"
      end
    end

    references do
      reference :label_set, on_delete: :restrict, match_with: [version_id: :version_id]
      reference :version, on_delete: :restrict, index?: true
    end

    check_constraints do
      check_constraint :position, "form_labels_check_0",
        check: "position BETWEEN 0 AND 2147483647"
    end
  end

  identities do
    identity :parent_key, [:label_set_id, :key]
  end
end
