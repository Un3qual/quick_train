defmodule QuickTrain.Projects.ProjectItem do
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

    timestamps()
  end

  relationships do
    belongs_to :project, QuickTrain.Projects.Project, allow_nil?: false, attribute_public?: true
    belongs_to :dataset, QuickTrain.Datasets.Dataset, allow_nil?: false, attribute_public?: true

    belongs_to :schema_version, QuickTrain.Datasets.DatasetSchemaVersion,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :item, QuickTrain.Datasets.DatasetItem, allow_nil?: false, attribute_public?: true

    belongs_to :revision, QuickTrain.Datasets.DatasetItemRevision,
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

    create :create_internal do
      accept [:project_id, :dataset_id, :schema_version_id, :item_id, :revision_id]
    end

    destroy :destroy_internal
  end

  policies do
    policy action(:read) do
      forbid_unless actor_attribute_equals(:status, "active")
      authorize_if relates_to_actor_via([:project, :reader_role_assignments, :user])
    end

    policy action(:read) do
      authorize_if accessing_from(Module.concat(["QuickTrain.Projects.Project"]), :items)
    end

    policy action(:list_scoped) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "projects.read"}
    end
  end

  graphql do
    type :project_item
    derive_filter? false
    derive_sort? false
    relationships []
  end

  postgres do
    table "project_items"
    repo QuickTrain.Repo
    migration_defaults id: "fragment(\"gen_random_uuid()\")"

    references do
      reference :project,
        on_delete: :restrict,
        match_with: [dataset_id: :dataset_id, schema_version_id: :schema_version_id]

      reference :dataset, on_delete: :restrict
      reference :schema_version, on_delete: :restrict, match_with: [dataset_id: :dataset_id]
      reference :item, on_delete: :restrict

      reference :revision,
        on_delete: :restrict,
        match_with: [
          item_id: :item_id,
          dataset_id: :dataset_id,
          schema_version_id: :schema_version_id
        ]
    end

    custom_indexes do
      index [:id, :project_id], unique: true
      index [:id, :project_id, :revision_id], unique: true
    end
  end

  identities do
    identity :project_item, [:project_id, :item_id]
  end
end
