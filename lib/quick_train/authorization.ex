defmodule QuickTrain.Authorization do
  @moduledoc "Fail-closed, organization-scoped role and capability checks."

  use Ash.Domain,
    otp_app: :quick_train,
    extensions: [AshGraphql.Domain]

  graphql do
    mutations do
      create QuickTrain.Authorization.Capability, :create_capability, :create
      create QuickTrain.Authorization.Role, :create_role, :create
      create QuickTrain.Authorization.RoleCapability, :grant_capability, :grant
      create QuickTrain.Authorization.RoleAssignment, :assign_role, :assign
    end
  end

  resources do
    resource QuickTrain.Authorization.Capability do
      define :create_capability, action: :create, args: [:key, :description]
    end

    resource QuickTrain.Authorization.Role do
      define :create_role, action: :create, args: [:organization_id, :key, :name]
    end

    resource QuickTrain.Authorization.RoleCapability do
      define :grant_capability, action: :grant, args: [:role_id, :capability_id]
    end

    resource QuickTrain.Authorization.RoleAssignment do
      define :assign_role, action: :assign, args: [:organization_id, :user_id, :role_id]
      define :allowed?, action: :allowed?, args: [:user_id, :organization_id, :capability_key]
    end

    resource QuickTrain.Authorization.Decision
  end
end
