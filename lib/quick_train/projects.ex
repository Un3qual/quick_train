defmodule QuickTrain.Projects do
  @moduledoc "Organization-owned project configuration, lifecycle, and worker admission."
  use Ash.Domain, otp_app: :quick_train, extensions: [AshGraphql.Domain]

  resources do
    resource QuickTrain.Projects.Project do
      define :configure_project, action: :configure
      define :rename_project, action: :rename

      define :lock_project,
        action: :lock,
        args: [:organization_id, :project_id],
        not_found_error?: false

      define :get_project, action: :get_scoped, args: [:organization_id, :id]
      define :list_projects, action: :list_scoped, args: [:organization_id]
      define :create_project, action: :create, args: [:organization_id]

      define :enroll_revisions, action: :enroll_revisions, args: [:organization_id, :project_id]

      define :remove_project_items,
        action: :remove_project_items,
        args: [:organization_id, :project_id]

      define :set_binding, action: :set_binding, args: [:organization_id, :project_id]
      define :set_slot_policy, action: :set_slot_policy, args: [:organization_id, :project_id]

      define :set_worker_access, action: :set_worker_access, args: [:organization_id, :project_id]

      define :remove_worker_access,
        action: :remove_worker_access,
        args: [:organization_id, :project_id]

      define :create_explicit_group,
        action: :create_explicit_group,
        args: [:organization_id, :project_id]

      define :remove_explicit_group,
        action: :remove_explicit_group,
        args: [:organization_id, :project_id]

      define :remove_binding, action: :remove_binding, args: [:organization_id, :project_id]

      define :remove_slot_policy,
        action: :remove_slot_policy,
        args: [:organization_id, :project_id]

      define :activate_project, action: :activate_record
      define :pause_project, action: :pause_record
      define :resume_project, action: :resume_record
      define :complete_project, action: :complete_record
      define :archive_project, action: :archive_record
    end

    resource QuickTrain.Projects.ProjectItem
    resource QuickTrain.Projects.ProjectInputBinding
    resource QuickTrain.Projects.ProjectSlotPolicy
    resource QuickTrain.Projects.ProjectWorkerAccess
    resource QuickTrain.Projects.ExplicitGroup
    resource QuickTrain.Projects.ExplicitGroupInput
  end

  graphql do
    queries do
      list QuickTrain.Projects.Project, :projects, :list_scoped,
        relay?: true,
        paginate_with: :keyset

      read_one QuickTrain.Projects.Project, :project, :get_scoped

      list QuickTrain.Projects.ProjectItem, :project_items, :list_scoped,
        relay?: true,
        paginate_with: :keyset

      list QuickTrain.Projects.ProjectInputBinding, :project_input_bindings, :list_scoped,
        relay?: true,
        paginate_with: :keyset

      list QuickTrain.Projects.ProjectSlotPolicy, :project_slot_policies, :list_scoped,
        relay?: true,
        paginate_with: :keyset

      list QuickTrain.Projects.ProjectWorkerAccess, :project_worker_access_entries, :list_scoped,
        relay?: true,
        paginate_with: :keyset

      list QuickTrain.Projects.ExplicitGroup, :explicit_groups, :list_scoped,
        relay?: true,
        paginate_with: :keyset

      list QuickTrain.Projects.ExplicitGroupInput, :explicit_group_inputs, :list_scoped,
        relay?: true,
        paginate_with: :keyset
    end

    mutations do
      create QuickTrain.Projects.Project, :create_project, :create

      update QuickTrain.Projects.Project, :update_project_draft, :configure,
        read_action: :get_for_update,
        identity: false

      update QuickTrain.Projects.Project, :update_project_title, :rename,
        read_action: :get_for_update,
        identity: false

      action QuickTrain.Projects.Project, :enroll_project_revisions, :enroll_revisions,
        args: [:organization_id, :project_id, :revision_ids]

      action QuickTrain.Projects.Project, :remove_project_items, :remove_project_items,
        args: [:organization_id, :project_id, :project_item_ids]

      action QuickTrain.Projects.Project, :set_project_input_binding, :set_binding,
        args: [:organization_id, :project_id, :requirement_id, :field_definition_id]

      action QuickTrain.Projects.Project, :remove_project_input_binding, :remove_binding,
        args: [:organization_id, :project_id, :requirement_id]

      action QuickTrain.Projects.Project, :set_project_slot_policy, :set_slot_policy,
        args: [:organization_id, :project_id, :input_slot_id, :item_count, :shuffle]

      action QuickTrain.Projects.Project, :remove_project_slot_policy, :remove_slot_policy,
        args: [:organization_id, :project_id, :input_slot_id]

      action QuickTrain.Projects.Project, :set_project_worker_access, :set_worker_access,
        args: [:organization_id, :project_id, :user_id, :disposition]

      action QuickTrain.Projects.Project, :remove_project_worker_access, :remove_worker_access,
        args: [:organization_id, :project_id, :user_id]

      action QuickTrain.Projects.Project, :create_project_explicit_group, :create_explicit_group,
        args: [:organization_id, :project_id, :position, :inputs]

      action QuickTrain.Projects.Project, :remove_project_explicit_group, :remove_explicit_group,
        args: [:organization_id, :project_id, :group_id]

      update QuickTrain.Projects.Project, :activate_project, :activate_record,
        read_action: :get_for_update,
        identity: false

      update QuickTrain.Projects.Project, :pause_project, :pause_record,
        read_action: :get_for_update,
        identity: false

      update QuickTrain.Projects.Project, :resume_project, :resume_record,
        read_action: :get_for_update,
        identity: false

      update QuickTrain.Projects.Project, :complete_project, :complete_record,
        read_action: :get_for_update,
        identity: false

      update QuickTrain.Projects.Project, :archive_project, :archive_record,
        read_action: :get_for_update,
        identity: false
    end
  end
end
