defmodule QuickTrain.Projects.ProjectInputBinding do
  @moduledoc "Organization-scoped project configuration."
  use Ash.Resource,
    primary_read_warning?: false,
    otp_app: :quick_train,
    domain: QuickTrain.Projects,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshGraphql.Resource],
    authorizers: [Ash.Policy.Authorizer]

  alias QuickTrain.Authorization.Checks.OrganizationCapability
  alias QuickTrain.Datasets.{DatasetFieldDefinition, DatasetRecordType, DatasetSchemaVersion}
  alias QuickTrain.Forms.FormVersion
  alias QuickTrain.Forms.Inputs.InputFieldRequirement
  alias QuickTrain.Projects.Project
  alias QuickTrain.Repo

  attributes do
    uuid_primary_key :id

    timestamps()
  end

  relationships do
    belongs_to :project, Project, allow_nil?: false, attribute_public?: true

    belongs_to :schema_version, DatasetSchemaVersion,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :root_record_type, DatasetRecordType,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :form_version, FormVersion,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :requirement, InputFieldRequirement,
      public?: true,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :field_definition, DatasetFieldDefinition,
      public?: true,
      allow_nil?: false,
      attribute_public?: true
  end

  actions do
    read :read do
      primary? true

      prepare build(sort: [inserted_at: :asc, id: :asc])

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

      prepare build(sort: [inserted_at: :asc, id: :asc])

      pagination keyset?: true,
                 required?: true,
                 default_limit: 50,
                 max_page_size: 100,
                 stable_sort: [inserted_at: :asc, id: :asc]
    end

    read :get_for_remove do
      get? true
      argument :project_id, :uuid, allow_nil?: false
      argument :requirement_id, :uuid, allow_nil?: false

      filter expr(
               project_id == ^arg(:project_id) and
                 requirement_id == ^arg(:requirement_id)
             )
    end

    create :set do
      upsert? true
      upsert_identity :project_requirement
      upsert_fields [:field_definition_id, :updated_at]

      argument :organization_id, :uuid, allow_nil?: false
      accept [:project_id, :requirement_id, :field_definition_id]
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
      authorize_if accessing_from(Project, :bindings)
    end

    policy action(:list_scoped) do
      authorize_if {OrganizationCapability, capability: "projects.read"}
    end
  end

  graphql do
    type :project_input_binding
    derive_filter? false
    derive_sort? false
    relationships [:requirement, :field_definition]
  end

  postgres do
    table "project_input_bindings"
    repo Repo

    references do
      reference :project,
        on_delete: :restrict,
        match_with: [
          schema_version_id: :schema_version_id,
          root_record_type_id: :root_record_type_id,
          form_version_id: :form_version_id
        ]

      reference :schema_version, on_delete: :restrict

      reference :root_record_type,
        on_delete: :restrict,
        match_with: [schema_version_id: :schema_version_id]

      reference :form_version, on_delete: :restrict
      reference :requirement, on_delete: :restrict, match_with: [form_version_id: :version_id]

      reference :field_definition,
        on_delete: :restrict,
        match_with: [root_record_type_id: :record_type_id]
    end
  end

  identities do
    identity :project_requirement, [:project_id, :requirement_id]
  end
end
