defmodule QuickTrain.Tasks.Task do
  @moduledoc "Scoped collection task evidence."
  use Ash.Resource,
    primary_read_warning?: false,
    otp_app: :quick_train,
    domain: QuickTrain.Tasks,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id

    timestamps()
  end

  relationships do
    has_many :inputs, QuickTrain.Tasks.TaskInput, destination_attribute: :task_id, public?: true

    has_many :attempts, QuickTrain.Tasks.Attempts.Attempt,
      destination_attribute: :task_id,
      public?: true

    has_many :outcomes, QuickTrain.Tasks.Responses.QuestionResponse,
      destination_attribute: :task_id,
      public?: true

    belongs_to :organization, QuickTrain.Organizations.Organization,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :project, QuickTrain.Projects.Project, allow_nil?: false, attribute_public?: true

    belongs_to :form_version, QuickTrain.Forms.FormVersion,
      allow_nil?: false,
      attribute_public?: true,
      public?: true

    belongs_to :explicit_group, QuickTrain.Projects.ExplicitGroup,
      allow_nil?: false,
      attribute_public?: true
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
    read :list_scoped do
      prepare build(context: %{shared: %{task_results: true}})
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

    create :create_internal do
      accept [
        :organization_id,
        :project_id,
        :form_version_id,
        :explicit_group_id
      ]
    end
  end

  policies do
    policy action(:read) do
      authorize_if Module.concat(["QuickTrain.Tasks.Access.ReadAccess"])
    end

    policy action([:list_scoped, :get_scoped]) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "tasks.results.read"}
    end

    policy action(:create_internal) do
      forbid_if always()
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
    repo QuickTrain.Repo

    references do
      reference :organization, on_delete: :restrict, name: "tasks_organization_scope_fkey"

      reference :project,
        on_delete: :restrict,
        name: "tasks_project_scope_fkey",
        match_with: [organization_id: :organization_id, form_version_id: :form_version_id]

      reference :form_version, on_delete: :restrict, name: "tasks_form_version_scope_fkey"

      reference :explicit_group,
        on_delete: :restrict,
        name: "tasks_explicit_group_scope_fkey",
        match_with: [project_id: :project_id, form_version_id: :form_version_id]
    end

    custom_indexes do
      index [:id, :project_id, :form_version_id], unique: true, name: "tasks_scope_0"
    end
  end

  identities do
    identity :explicit_group, [:explicit_group_id]
  end
end
