defmodule QuickTrain.Accounts do
  @moduledoc "Global user accounts, external identities, and account-required sessions."

  use Ash.Domain,
    otp_app: :quick_train,
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
      define :register_user, action: :register, args: [:email, :display_name]
      define :list_active_users, action: :list_active
      define :get_user, action: :read, get_by: [:id]
    end

    resource QuickTrain.Accounts.Session do
      define :issue_session, action: :issue, args: [:user_id]
      define :revoke_session, action: :revoke
    end

    resource QuickTrain.Accounts.ExternalIdentity
    resource QuickTrain.Accounts.OidcLoginTransaction
    resource QuickTrain.Accounts.AuthenticationEvent
  end
end
