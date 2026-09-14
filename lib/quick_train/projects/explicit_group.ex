defmodule QuickTrain.Projects.ExplicitGroup do
  @moduledoc "Organization-scoped project configuration."
  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Projects,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshGraphql.Resource],
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      generated?: true,
      public?: true,
      writable?: false

    attribute :position, :integer,
      public?: true,
      allow_nil?: false,
      constraints: [min: 0, max: 2_147_483_647]

    attribute :canonical_key, :binary, allow_nil?: false
    timestamps()
  end

  relationships do
    belongs_to :project, QuickTrain.Projects.Project, allow_nil?: false, attribute_public?: true

    belongs_to :form_version, QuickTrain.Forms.FormVersion,
      allow_nil?: false,
      attribute_public?: true

    has_many :inputs, QuickTrain.Projects.ExplicitGroupInput,
      destination_attribute: :group_id,
      public?: true
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

    read :get_scoped do
      get? true
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      argument :id, :uuid, allow_nil?: false

      filter expr(
               id == ^arg(:id) and project_id == ^arg(:project_id) and
                 project.organization_id == ^arg(:organization_id)
             )
    end

    create :create_internal do
      accept [:position, :canonical_key, :project_id, :form_version_id]
    end

    destroy :destroy_internal
  end

  policies do
    policy action(:read) do
      forbid_unless actor_attribute_equals(:status, "active")
      authorize_if relates_to_actor_via([:project, :reader_role_assignments, :user])
    end

    policy action(:read) do
      authorize_if accessing_from(
                     Module.concat(["QuickTrain.Projects.Project"]),
                     :explicit_groups
                   )
    end

    policy action([:list_scoped, :get_scoped]) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "projects.read"}
    end
  end

  graphql do
    type :project_explicit_group
    derive_filter? false
    derive_sort? false
    relationships [:inputs]
    paginate_relationship_with inputs: :relay
  end

  postgres do
    table "project_explicit_groups"
    repo QuickTrain.Repo
    migration_defaults id: "fragment(\"gen_random_uuid()\")"

    references do
      reference :project, on_delete: :restrict, match_with: [form_version_id: :form_version_id]
      reference :form_version, on_delete: :restrict
    end

    custom_indexes do
      index [:id, :project_id, :form_version_id], unique: true
    end

    check_constraints do
      check_constraint :position, "project_explicit_groups_position_check",
        check: "position BETWEEN 0 AND 2147483647"
    end
  end

  identities do
    identity :project_position, [:project_id, :position]
    identity :project_group, [:project_id, :canonical_key]
  end
end
