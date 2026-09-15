defmodule QuickTrain.Projects.ExplicitGroupInput do
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
  alias QuickTrain.Projects.{ExplicitGroup, Project, ProjectItem}
  alias QuickTrain.Repo

  attributes do
    uuid_primary_key :id

    attribute :position, :integer,
      public?: true,
      allow_nil?: false,
      constraints: [min: 0, max: 2_147_483_647]

    timestamps()
  end

  relationships do
    belongs_to :project, Project, allow_nil?: false, attribute_public?: true

    belongs_to :form_version, FormVersion,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :group, ExplicitGroup,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :project_item, ProjectItem,
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
                 stable_sort: [position: :asc, id: :asc]
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
                 stable_sort: [position: :asc, id: :asc]
    end

    create :create_internal do
      accept [
        :position,
        :project_id,
        :form_version_id,
        :group_id,
        :project_item_id,
        :input_slot_id
      ]
    end

    destroy :destroy_internal
  end

  policies do
    policy action(:read) do
      forbid_unless actor_attribute_equals(:status, "active")
      authorize_if relates_to_actor_via([:project, :reader_role_assignments, :user])
    end

    policy action(:read) do
      authorize_if accessing_from(Project, :group_inputs)
      authorize_if accessing_from(ExplicitGroup, :inputs)
    end

    policy action(:list_scoped) do
      authorize_if {OrganizationCapability, capability: "projects.read"}
    end
  end

  graphql do
    type :project_explicit_group_input
    derive_filter? false
    derive_sort? false
    relationships []
  end

  postgres do
    table "project_explicit_group_inputs"
    repo Repo

    references do
      reference :project, on_delete: :restrict, match_with: [form_version_id: :form_version_id]
      reference :form_version, on_delete: :restrict

      reference :group,
        on_delete: :delete,
        match_with: [project_id: :project_id, form_version_id: :form_version_id]

      reference :project_item, on_delete: :restrict, match_with: [project_id: :project_id]
      reference :input_slot, on_delete: :restrict, match_with: [form_version_id: :version_id]
    end

    check_constraints do
      check_constraint :position, "project_explicit_group_inputs_position_check",
        check: "position BETWEEN 0 AND 2147483647"
    end
  end

  identities do
    identity :group_item, [:group_id, :project_item_id]
    identity :group_slot_position, [:group_id, :input_slot_id, :position]
  end
end
