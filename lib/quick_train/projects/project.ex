defmodule QuickTrain.Projects.Project do
  @moduledoc "One organization-owned, frozen collection run."
  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Projects,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshGraphql.Resource],
    authorizers: [Ash.Policy.Authorizer]

  alias QuickTrain.Authorization.RoleAssignment
  alias QuickTrain.Projects.Error

  attributes do
    uuid_primary_key :id

    attribute :title, :string, public?: true, allow_nil?: false, constraints: [match: ~r/\S/u]

    attribute :state, :atom,
      public?: true,
      allow_nil?: false,
      default: :draft,
      constraints: [one_of: [:draft, :active, :paused, :completed, :archived]]

    attribute :audience, :atom,
      public?: true,
      allow_nil?: false,
      default: :organization_members,
      constraints: [one_of: [:organization_members, :external_users, :both]]

    attribute :external_access, :atom,
      public?: true,
      allow_nil?: false,
      default: :allowlisted,
      constraints: [one_of: [:open, :allowlisted]]

    attribute :review_mode, :atom,
      public?: true,
      allow_nil?: false,
      default: :automatic,
      constraints: [one_of: [:automatic, :manual]]

    attribute :submission_target, :integer,
      public?: true,
      allow_nil?: false,
      default: 1,
      constraints: [min: 1, max: 2_147_483_647]

    attribute :skip_allowed, :boolean, public?: true, allow_nil?: false, default: false
    attribute :reason_required, :boolean, public?: true, allow_nil?: false, default: false

    attribute :lease_minutes, :integer,
      public?: true,
      allow_nil?: false,
      default: 30,
      constraints: [min: 1, max: 120]

    attribute :activated_at, :utc_datetime_usec, public?: true
    attribute :completed_at, :utc_datetime_usec, public?: true
    attribute :archived_at, :utc_datetime_usec, public?: true
    timestamps()
  end

  relationships do
    belongs_to :organization, QuickTrain.Organizations.Organization,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :dataset, QuickTrain.Datasets.Dataset, allow_nil?: false, attribute_public?: true

    belongs_to :schema_version, QuickTrain.Datasets.DatasetSchemaVersion,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :root_record_type, QuickTrain.Datasets.DatasetRecordType,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :form, QuickTrain.Forms.Form, allow_nil?: false, attribute_public?: true

    belongs_to :form_version, QuickTrain.Forms.FormVersion,
      allow_nil?: false,
      attribute_public?: true

    has_many :items, QuickTrain.Projects.ProjectItem,
      destination_attribute: :project_id,
      public?: true

    has_many :bindings, QuickTrain.Projects.ProjectInputBinding,
      destination_attribute: :project_id,
      public?: true

    has_many :slot_policies, QuickTrain.Projects.ProjectSlotPolicy,
      destination_attribute: :project_id,
      public?: true

    has_many :worker_access, QuickTrain.Projects.ProjectWorkerAccess,
      destination_attribute: :project_id,
      public?: true

    has_many :explicit_groups, QuickTrain.Projects.ExplicitGroup,
      destination_attribute: :project_id,
      public?: true

    has_many :group_inputs, QuickTrain.Projects.ExplicitGroupInput,
      destination_attribute: :project_id,
      public?: true

    has_many :reader_role_assignments, QuickTrain.Authorization.RoleAssignment do
      source_attribute :organization_id
      destination_attribute :organization_id

      filter expr(
               user.status == "active" and organization.status == "active" and
                 exists(
                   role.role_capabilities,
                   capability.key in ["projects.read", "projects.manage"]
                 ) and
                 exists(organization.memberships, user_id == ^actor(:id) and status == "active")
             )
    end
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
      filter expr(organization_id == ^arg(:organization_id))

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
      filter expr(id == ^arg(:id) and organization_id == ^arg(:organization_id))
    end

    read :get_for_update do
      get? true
      argument :organization_id, :uuid, allow_nil?: false
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id) and organization_id == ^arg(:organization_id))
    end

    read :lock do
      get? true
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:project_id) and organization_id == ^arg(:organization_id))
      prepare build(lock: :for_update)
    end

    action :enroll_revisions, :struct do
      transaction? true
      allow_nil? false
      constraints instance_of: __MODULE__
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      argument :revision_ids, {:array, :uuid}, allow_nil?: false, constraints: [min_length: 1]
      run Module.concat(["QuickTrain.Projects.Management"])
    end

    action :remove_project_items, :struct do
      transaction? true
      allow_nil? false
      constraints instance_of: __MODULE__
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      argument :project_item_ids, {:array, :uuid}, allow_nil?: false, constraints: [min_length: 1]
      run Module.concat(["QuickTrain.Projects.Management"])
    end

    action :set_binding, :struct do
      transaction? true
      allow_nil? false
      constraints instance_of: __MODULE__
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      argument :requirement_id, :uuid, allow_nil?: false
      argument :field_definition_id, :uuid, allow_nil?: false
      run Module.concat(["QuickTrain.Projects.Management"])
    end

    action :set_slot_policy, :struct do
      transaction? true
      allow_nil? false
      constraints instance_of: __MODULE__
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      argument :input_slot_id, :uuid, allow_nil?: false
      argument :item_count, :integer, allow_nil?: false, constraints: [min: 1, max: 2_147_483_647]
      argument :shuffle, :boolean, allow_nil?: false
      run Module.concat(["QuickTrain.Projects.Management"])
    end

    action :set_worker_access, :struct do
      transaction? true
      allow_nil? false
      constraints instance_of: __MODULE__
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      argument :user_id, :uuid, allow_nil?: false
      argument :disposition, :atom, allow_nil?: false, constraints: [one_of: [:allow, :block]]
      run Module.concat(["QuickTrain.Projects.Management"])
    end

    action :remove_worker_access, :struct do
      transaction? true
      allow_nil? false
      constraints instance_of: __MODULE__
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      argument :user_id, :uuid, allow_nil?: false
      run Module.concat(["QuickTrain.Projects.Management"])
    end

    action :create_explicit_group, :struct do
      transaction? true
      allow_nil? false
      constraints instance_of: __MODULE__
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      argument :position, :integer, allow_nil?: false, constraints: [min: 0, max: 2_147_483_647]
      argument :inputs, {:array, QuickTrain.Projects.GroupInput}, allow_nil?: false
      run Module.concat(["QuickTrain.Projects.Management"])
    end

    action :remove_explicit_group, :struct do
      transaction? true
      allow_nil? false
      constraints instance_of: __MODULE__
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      argument :group_id, :uuid, allow_nil?: false
      run Module.concat(["QuickTrain.Projects.Management"])
    end

    action :remove_binding, :struct do
      transaction? true
      allow_nil? false
      constraints instance_of: __MODULE__
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      argument :requirement_id, :uuid, allow_nil?: false
      run Module.concat(["QuickTrain.Projects.Management"])
    end

    action :remove_slot_policy, :struct do
      transaction? true
      allow_nil? false
      constraints instance_of: __MODULE__
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      argument :input_slot_id, :uuid, allow_nil?: false
      run Module.concat(["QuickTrain.Projects.Management"])
    end

    create :create do
      accept [
        :title,
        :organization_id,
        :dataset_id,
        :schema_version_id,
        :form_version_id,
        :audience,
        :external_access,
        :review_mode,
        :submission_target,
        :skip_allowed,
        :reason_required,
        :lease_minutes
      ]

      change Module.concat(["QuickTrain.Projects.Project.Changes.Configure"])
    end

    update :configure do
      require_atomic? false

      accept [
        :title,
        :audience,
        :external_access,
        :review_mode,
        :submission_target,
        :skip_allowed,
        :reason_required,
        :lease_minutes
      ]

      change get_and_lock(:for_update)
      change Module.concat(["QuickTrain.Projects.Project.Changes.Configure"])
    end

    update :rename do
      accept []
      argument :title, :string, allow_nil?: false
      change set_attribute(:title, arg(:title))
    end

    for {action, source, target} <- [
          {:activate_record, [:draft], :active},
          {:complete_record, [:active, :paused], :completed}
        ] do
      update action do
        accept []
        require_atomic? false
        change get_and_lock(:for_update)
        change set_attribute(:state, target)

        change {Module.concat(["QuickTrain.Projects.Project.Changes.Transition"]),
                from: source, to: target}
      end
    end

    for {action, source, target} <- [
          {:pause_record, :active, :paused},
          {:resume_record, :paused, :active},
          {:archive_record, :completed, :archived}
        ] do
      update action do
        accept []

        change atomic_update(
                 :state,
                 expr(
                   if state in ^[source, target] do
                     ^target
                   else
                     error(^Error, %{category: :invalid_project_transition})
                   end
                 )
               )

        change atomic_update(:updated_at, expr(if state == ^target, do: updated_at, else: now()))

        if action == :archive_record do
          change atomic_update(
                   :archived_at,
                   expr(if state == :archived, do: archived_at, else: now())
                 )
        end
      end
    end
  end

  policies do
    policy action(:read) do
      forbid_if always()
    end

    policy action([:get_scoped, :list_scoped]) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "projects.read"}
    end

    policy action([
             :remove_slot_policy,
             :remove_binding,
             :get_for_update,
             :create,
             :configure,
             :activate_record,
             :complete_record,
             :enroll_revisions,
             :remove_project_items,
             :set_binding,
             :set_slot_policy,
             :set_worker_access,
             :remove_worker_access,
             :create_explicit_group,
             :remove_explicit_group
           ]) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "projects.manage"}
    end

    policy action([:rename, :pause_record, :resume_record, :archive_record]) do
      forbid_unless actor_attribute_equals(:status, "active")

      authorize_if expr(
                     exists(
                       RoleAssignment,
                       organization_id == parent(organization_id) and user_id == ^actor(:id) and
                         user.status == "active" and organization.status == "active" and
                         exists(role.role_capabilities, capability.key == "projects.manage") and
                         exists(
                           organization.memberships,
                           user_id == ^actor(:id) and status == "active"
                         )
                     )
                   )
    end
  end

  graphql do
    type :project
    derive_filter? false
    derive_sort? false

    relationships [
      :items,
      :bindings,
      :slot_policies,
      :worker_access,
      :explicit_groups,
      :group_inputs
    ]

    paginate_relationship_with items: :relay,
                               bindings: :relay,
                               slot_policies: :relay,
                               worker_access: :relay,
                               explicit_groups: :relay,
                               group_inputs: :relay
  end

  postgres do
    table "projects"
    repo QuickTrain.Repo

    references do
      reference :organization, on_delete: :restrict
      reference :dataset, on_delete: :restrict, match_with: [organization_id: :organization_id]

      reference :schema_version,
        on_delete: :restrict,
        match_with: [dataset_id: :dataset_id, root_record_type_id: :root_record_type_id]

      reference :root_record_type,
        on_delete: :restrict,
        match_with: [schema_version_id: :schema_version_id]

      reference :form, on_delete: :restrict, match_with: [organization_id: :organization_id]
      reference :form_version, on_delete: :restrict, match_with: [form_id: :form_id]
    end

    custom_indexes do
      index [:id, :organization_id], unique: true
      index [:id, :organization_id, :form_version_id], unique: true
      index [:id, :dataset_id, :schema_version_id], unique: true
      index [:id, :schema_version_id, :root_record_type_id, :form_version_id], unique: true
      index [:id, :form_version_id], unique: true
    end

    check_constraints do
      check_constraint :state, "projects_state_check",
        check: "state IN ('draft', 'active', 'paused', 'completed', 'archived')"

      check_constraint :submission_target, "projects_submission_target_check",
        check: "submission_target BETWEEN 1 AND 2147483647"

      check_constraint :lease_minutes, "projects_lease_check",
        check: "lease_minutes BETWEEN 1 AND 120"

      check_constraint :audience, "projects_audience_check",
        check: "audience IN ('organization_members', 'external_users', 'both')"

      check_constraint :external_access, "projects_external_access_check",
        check: "external_access IN ('open', 'allowlisted')"

      check_constraint :review_mode, "projects_review_check",
        check: "review_mode IN ('automatic', 'manual')"
    end
  end
end
