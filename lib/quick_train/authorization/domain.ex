defmodule QuickTrain.Authorization.Domain do
  @moduledoc false

  use Ash.Domain, otp_app: :quick_train, validate_config_inclusion?: false

  resources do
    resource QuickTrain.Authorization.Capability
    resource QuickTrain.Authorization.Role
    resource QuickTrain.Authorization.RoleCapability
    resource QuickTrain.Authorization.RoleAssignment
    resource QuickTrain.Authorization.Decision
  end
end
