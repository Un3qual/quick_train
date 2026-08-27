defmodule QuickTrain.EnterpriseIdentity.Domain do
  @moduledoc false

  use Ash.Domain,
    otp_app: :quick_train,
    validate_config_inclusion?: false,
    extensions: [AshGraphql.Domain]

  graphql do
    mutations do
    end

    queries do
    end

  end

  resources do
    resource QuickTrain.EnterpriseIdentity.EnterpriseConnection
    resource QuickTrain.EnterpriseIdentity.Directory
    resource QuickTrain.EnterpriseIdentity.DirectoryUser
    resource QuickTrain.EnterpriseIdentity.DirectoryGroup
    resource QuickTrain.EnterpriseIdentity.DirectoryMembership
    resource QuickTrain.EnterpriseIdentity.ExternalGroupRoleMapping
  end
end
