defmodule QuickTrain.Projects.ProjectSlotPolicy do
  @moduledoc "Organization-scoped project configuration."
  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Projects,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshGraphql.Resource],
    authorizers: [Ash.Policy.Authorizer]

  alias QuickTrain.Authorization.Checks.OrganizationCapability
  alias QuickTrain.Forms.FormVersion
  alias QuickTrain.Forms.Inputs.InputSlotDefinition
  alias QuickTrain.Projects.Project
  alias QuickTrain.Repo

  attributes do
    uuid_primary_key :id

    attribute :item_count, :integer,
      public?: true,
      allow_nil?: false,
      constraints: [min: 1, max: 2_147_483_647]

    attribute :shuffle, :boolean, public?: true, allow_nil?: false, default: false
    timestamps()
  end

  relationships do
    belongs_to :project, Project, allow_nil?: false, attribute_public?: true

    belongs_to :form_version, FormVersion,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :input_slot, InputSlotDefinition,
      allow_nil?: false,
      attribute_public?: true
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
      argument :project_id, :uuid, allow_nil?: false

      filter expr(
               project_id == ^arg(:project_id) and
                 project.organization_id == ^arg(:organization_id)
             )

      pagination keyset?: true,
                 required?: true,
                 default_limit: 50,
                 max_page_size: 100,
                 stable_sort: [inserted_at: :asc, id: :asc]
    end

    read :get_for_remove do
      get? true
      argument :project_id, :uuid, allow_nil?: false
      argument :input_slot_id, :uuid, allow_nil?: false

      filter expr(
               project_id == ^arg(:project_id) and
                 input_slot_id == ^arg(:input_slot_id)
             )
    end

    create :set do
      upsert? true
      upsert_identity :project_slot
      upsert_fields [:item_count, :shuffle, :updated_at]
      argument :organization_id, :uuid, allow_nil?: false
      accept [:project_id, :input_slot_id, :item_count, :shuffle]
      change Module.concat(["QuickTrain.Projects.Changes.ConfigureChild"])
    end

    destroy :remove do
      argument :organization_id, :uuid, allow_nil?: false
      require_atomic? false
      change Module.concat(["QuickTrain.Projects.Changes.ConfigureChild"])
    end
  end

  policies do
    policy action(:get_for_remove) do
      authorize_if expr(
                     exists(
                       project.reader_role_assignments,
                       user_id == ^actor(:id) and
                         exists(role.role_capabilities, capability.key == "projects.manage")
                     )
                   )
    end

    policy action([:set, :remove]) do
      authorize_if {OrganizationCapability, capability: "projects.manage"}
    end

    policy action(:read) do
      forbid_unless actor_attribute_equals(:status, "active")
      authorize_if relates_to_actor_via([:project, :reader_role_assignments, :user])
    end

    policy action(:read) do
      authorize_if accessing_from(Project, :slot_policies)
    end

    policy action(:list_scoped) do
      authorize_if {OrganizationCapability, capability: "projects.read"}
    end
  end

  graphql do
    type :project_slot_policy
    derive_filter? false
    derive_sort? false
    relationships []
  end

  postgres do
    table "project_slot_policies"
    repo Repo

    references do
      reference :project, on_delete: :restrict, match_with: [form_version_id: :form_version_id]
      reference :form_version, on_delete: :restrict
      reference :input_slot, on_delete: :restrict, match_with: [form_version_id: :version_id]
    end

    custom_indexes do
      index [:id, :project_id], unique: true
    end

    check_constraints do
      check_constraint :item_count, "project_slot_policies_item_count_check",
        check: "item_count BETWEEN 1 AND 2147483647"
    end
  end

  identities do
    identity :project_slot, [:project_id, :input_slot_id]
  end
end
