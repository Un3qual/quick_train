defmodule QuickTrain.Tasks.Task do
  @moduledoc "Scoped collection task evidence."
  use Ash.Resource,
    primary_read_warning?: false,
    otp_app: :quick_train,
    domain: QuickTrain.Tasks,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias QuickTrain.Authorization.Checks.OrganizationCapability
  alias QuickTrain.Forms.FormVersion
  alias QuickTrain.Organizations.Organization
  alias QuickTrain.Projects.Project
  alias QuickTrain.Repo
  alias QuickTrain.Tasks.Access.ReadAccess
  alias QuickTrain.Tasks.Attempts.Attempt
  alias QuickTrain.Tasks.Responses.QuestionResponse
  alias QuickTrain.Tasks.Task.Input
  alias QuickTrain.Tasks.TaskInput

  attributes do
    uuid_primary_key :id

    attribute :position, :integer,
      public?: true,
      allow_nil?: false,
      constraints: [min: 0, max: 2_147_483_647]

    attribute :canonical_key, :binary, allow_nil?: false

    timestamps()
  end

  relationships do
    has_many :inputs, TaskInput, destination_attribute: :task_id, public?: true

    has_many :attempts, Attempt,
      destination_attribute: :task_id,
      public?: true

    has_many :outcomes, QuestionResponse,
      destination_attribute: :task_id,
      public?: true

    belongs_to :organization, Organization,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :project, Project, allow_nil?: false, attribute_public?: true

    belongs_to :form_version, FormVersion,
      allow_nil?: false,
      attribute_public?: true,
      public?: true
  end

  aggregates do
    count :submitted_count, :attempts do
      filter expr(state == :submitted)
      authorize? false
    end

    count :live_count, :attempts do
      filter expr(state in [:claimed, :assigned, :in_progress])
      authorize? false
    end
  end

  calculations do
    calculate :state,
              :atom,
              expr(
                cond do
                  submitted_count >= project.submission_target -> :satisfied
                  project.state in [:completed, :archived] -> :cancelled
                  true -> :open
                end
              ), public?: true, constraints: [one_of: [:open, :satisfied, :cancelled]]
  end

  preparations do
    prepare build(load: [:state])
  end

  actions do
    read :read_authored do
      pagination keyset?: true,
                 required?: false,
                 default_limit: 50,
                 max_page_size: 100,
                 stable_sort: [position: :asc, id: :asc]
    end

    read :get_for_remove do
      get? true
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      argument :id, :uuid, allow_nil?: false

      filter expr(
               id == ^arg(:id) and project_id == ^arg(:project_id) and
                 organization_id == ^arg(:organization_id)
             )
    end

    read :list_scoped do
      prepare build(context: %{shared: %{task_results: true}})
      filter expr(exists(attempts, true))
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      filter expr(organization_id == ^arg(:organization_id) and project_id == ^arg(:project_id))
      prepare build(sort: [id: :asc])

      pagination keyset?: true,
                 required?: true,
                 default_limit: 50,
                 max_page_size: 100,
                 stable_sort: [id: :asc]
    end

    read :get_scoped do
      prepare build(context: %{shared: %{task_results: true}})
      filter expr(exists(attempts, true))
      get? true
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id))
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      filter expr(organization_id == ^arg(:organization_id) and project_id == ^arg(:project_id))
    end

    read :read do
      primary? true

      prepare build(sort: [id: :asc])

      pagination keyset?: true,
                 required?: false,
                 default_limit: 50,
                 max_page_size: 100,
                 stable_sort: [id: :asc]
    end

    create :create do
      accept [:organization_id, :project_id, :position]
      argument :inputs, {:array, Input}, allow_nil?: false, constraints: [min_length: 1]
      change Module.concat(["QuickTrain.Tasks.Task.Changes.Configure"])
    end

    destroy :remove do
      argument :organization_id, :uuid, allow_nil?: false
      require_atomic? false
      change Module.concat(["QuickTrain.Tasks.Task.Changes.Configure"])
    end
  end

  policies do
    policy action(:read) do
      authorize_if ReadAccess
    end

    policy action([:list_scoped, :get_scoped]) do
      authorize_if {OrganizationCapability, capability: "tasks.results.read"}
    end

    policy action([:create, :get_for_remove, :remove]) do
      authorize_if {OrganizationCapability, capability: "projects.manage"}
    end

    policy action(:read_authored) do
      forbid_unless actor_attribute_equals(:status, "active")
      authorize_if relates_to_actor_via([:project, :reader_role_assignments, :user])
    end
  end

  graphql do
    type :task
    derive_filter? false
    derive_sort? false

    paginate_relationship_with inputs: :relay,
                               attempts: :relay,
                               outcomes: :relay

    relationships [:inputs, :attempts, :outcomes, :form_version]
  end

  postgres do
    table "tasks"
    repo Repo

    references do
      reference :organization, on_delete: :restrict, name: "tasks_organization_scope_fkey"

      reference :project,
        on_delete: :restrict,
        name: "tasks_project_scope_fkey",
        match_with: [organization_id: :organization_id, form_version_id: :form_version_id]

      reference :form_version, on_delete: :restrict, name: "tasks_form_version_scope_fkey"
    end

    custom_indexes do
      index [:id, :project_id, :form_version_id], unique: true, name: "tasks_scope_0"
    end
  end

  identities do
    identity :project_position, [:project_id, :position]
    identity :project_membership, [:project_id, :canonical_key]
  end
end
