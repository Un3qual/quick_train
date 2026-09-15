defmodule QuickTrain.Projects do
  @moduledoc "Organization-owned project configuration, lifecycle, and worker admission."
  use Ash.Domain, otp_app: :quick_train, extensions: [AshGraphql.Domain]

  alias QuickTrain.Projects.{
    ExplicitGroup,
    ExplicitGroupInput,
    Project,
    ProjectInputBinding,
    ProjectItem,
    ProjectSlotPolicy,
    ProjectWorkerAccess
  }

  resources do
    resource Project do
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

      define :create_explicit_group,
        action: :create_explicit_group,
        args: [:organization_id, :project_id]

      define :remove_explicit_group,
        action: :remove_explicit_group,
        args: [:organization_id, :project_id]

      define :activate_project, action: :activate_record
      define :pause_project, action: :pause_record
      define :resume_project, action: :resume_record
      define :complete_project, action: :complete_record
      define :archive_project, action: :archive_record
    end

    resource ProjectItem

    resource ProjectInputBinding do
      define :set_binding, action: :set, args: [:organization_id, :project_id]
      define :remove_binding, action: :remove, args: [:organization_id]
    end

    resource ProjectSlotPolicy do
      define :set_slot_policy, action: :set, args: [:organization_id, :project_id]
      define :remove_slot_policy, action: :remove, args: [:organization_id]
    end

    resource ProjectWorkerAccess do
      define :set_worker_access, action: :set, args: [:organization_id, :project_id]
      define :remove_worker_access, action: :remove, args: [:organization_id]
    end

    resource ExplicitGroup
    resource ExplicitGroupInput
  end

  graphql do
    queries do
      list Project, :projects, :list_scoped,
        relay?: true,
        paginate_with: :keyset

      read_one Project, :project, :get_scoped

      list ProjectItem, :project_items, :list_scoped,
        relay?: true,
        paginate_with: :keyset

      list ProjectInputBinding, :project_input_bindings, :list_scoped,
        relay?: true,
        paginate_with: :keyset

      list ProjectSlotPolicy, :project_slot_policies, :list_scoped,
        relay?: true,
        paginate_with: :keyset

      list ProjectWorkerAccess, :project_worker_access_entries, :list_scoped,
        relay?: true,
        paginate_with: :keyset

      list ExplicitGroup, :explicit_groups, :list_scoped,
        relay?: true,
        paginate_with: :keyset

      list ExplicitGroupInput, :explicit_group_inputs, :list_scoped,
        relay?: true,
        paginate_with: :keyset
    end

    mutations do
      create Project, :create_project, :create

      update Project, :update_project_draft, :configure,
        read_action: :get_for_update,
        identity: false

      update Project, :update_project_title, :rename,
        read_action: :get_for_update,
        identity: false

      action Project, :enroll_project_revisions, :enroll_revisions,
        args: [:organization_id, :project_id, :revision_ids]

      action Project, :remove_project_items, :remove_project_items,
        args: [:organization_id, :project_id, :project_item_ids]

      create ProjectInputBinding, :set_project_input_binding, :set

      destroy ProjectInputBinding, :remove_project_input_binding, :remove,
        read_action: :get_for_remove,
        args: [:organization_id],
        identity: false

      create ProjectSlotPolicy, :set_project_slot_policy, :set

      destroy ProjectSlotPolicy, :remove_project_slot_policy, :remove,
        read_action: :get_for_remove,
        args: [:organization_id],
        identity: false

      create ProjectWorkerAccess, :set_project_worker_access, :set

      destroy ProjectWorkerAccess, :remove_project_worker_access, :remove,
        read_action: :get_for_remove,
        args: [:organization_id],
        identity: false

      action Project, :create_project_explicit_group, :create_explicit_group,
        args: [:organization_id, :project_id, :position, :inputs]

      action Project, :remove_project_explicit_group, :remove_explicit_group,
        args: [:organization_id, :project_id, :group_id]

      update Project, :activate_project, :activate_record,
        read_action: :get_for_update,
        identity: false

      update Project, :pause_project, :pause_record,
        read_action: :get_for_update,
        identity: false

      update Project, :resume_project, :resume_record,
        read_action: :get_for_update,
        identity: false

      update Project, :complete_project, :complete_record,
        read_action: :get_for_update,
        identity: false

      update Project, :archive_project, :archive_record,
        read_action: :get_for_update,
        identity: false
    end
  end
end
