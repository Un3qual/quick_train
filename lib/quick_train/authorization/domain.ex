defmodule QuickTrain.Authorization.Domain do
  @moduledoc false

  use Ash.Domain,
    otp_app: :quick_train,
    validate_config_inclusion?: false,
    extensions: [AshGraphql.Domain]

  alias QuickTrain.Authorization.{Capability, Role, RoleCapability, RoleAssignment, Decision}

  graphql do
    authorize? false
    queries do

    end

    mutations do
      create Capability, :create_capability, :create
      create Role, :create_role, :create
      create RoleCapability, :grant_capability, :grant
      create RoleAssignment, :assign_role, :assign
    end
  end


  resources do
    resource Capability do
      define :create_capability, action: :create
    end

    resource Role do
      define :create_role, action: :create
    end

    resource RoleCapability do
      define :grant_capability, action: :grant
    end

    resource RoleAssignment do
      define :assign_role, action: :assign
    end
    resource Decision
  end
end
