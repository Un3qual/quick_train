defmodule QuickTrain.Accounts.Domain do
  @moduledoc false

  use Ash.Domain,
    otp_app: :quick_train,
    validate_config_inclusion?: false,
    extensions: [AshGraphql.Domain]

  graphql do
    authorize? false
    queries do
      list QuickTrain.Accounts.User, :all_users, :list_active, relay?: true
      read_one QuickTrain.Accounts.User, :get_user, :read
    end

    mutations do
      create QuickTrain.Accounts.User, :create_user, :register
    end
  end

  resources do
    resource QuickTrain.Accounts.User do
      define :create_user, action: :register
      define :all_users, action: :list_active
      define :get_user, action: :read
    end
    resource QuickTrain.Accounts.ExternalIdentity
    resource QuickTrain.Accounts.Session
    resource QuickTrain.Accounts.OidcLoginTransaction
    resource QuickTrain.Accounts.AuthenticationEvent
  end
end
