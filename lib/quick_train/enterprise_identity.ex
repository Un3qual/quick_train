defmodule QuickTrain.EnterpriseIdentity do
  @moduledoc "Provider-neutral enterprise SSO and directory synchronization boundaries."

  use Ash.Domain,
    otp_app: :quick_train,
    extensions: [AshGraphql.Domain]

  resources do
    resource QuickTrain.EnterpriseIdentity.EnterpriseConnection do
      define :create_connection,
        action: :create,
        args: [:organization_id, :provider, :external_id]

      define :get_enterprise_connection, action: :read, get_by: [:id]
    end

    resource QuickTrain.EnterpriseIdentity.Directory do
      define :create_directory, action: :create, args: [:enterprise_connection_id, :external_id]
    end

    resource QuickTrain.EnterpriseIdentity.DirectoryUser do
      define :link_directory_user,
        action: :link,
        args: [:enterprise_connection_id, :membership_id, :user_id, :external_id]

      define :get_directory_user, action: :read, get_by: [:id]
      define :deprovision_directory_user, action: :deprovision
    end

    resource QuickTrain.EnterpriseIdentity.DirectoryGroup do
      define :create_directory_group,
        action: :create,
        args: [:directory_id, :external_id, :name]

      define :get_directory_group, action: :read, get_by: [:id]
    end

    resource QuickTrain.EnterpriseIdentity.DirectoryMembership do
      define :add_directory_user_to_group,
        action: :create,
        args: [:directory_user_id, :directory_group_id]
    end

    resource QuickTrain.EnterpriseIdentity.ExternalGroupRoleMapping do
      define :map_directory_group_role,
        action: :map,
        args: [:directory_group_id, :role_id]

      define :unmap_directory_group_role, action: :unmap
    end
  end
end
