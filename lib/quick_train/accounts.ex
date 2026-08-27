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

    resource QuickTrain.Accounts.ExternalIdentity do
      define :link_external_identity,
        action: :link,
        args: [:user_id, :provider, :subject]

      define :get_external_identity, action: :read, get_by: [:provider, :subject]
      define :refresh_external_identity, action: :refresh
    end

    resource QuickTrain.Accounts.OidcLoginTransaction do
      define :begin_oidc_login,
        action: :begin,
        args: [:state_hash, :code_verifier, :expires_at]

      define :get_oidc_login, action: :read, get_by: [:state_hash]
      define :consume_oidc_login, action: :consume
      define :discard_oidc_login, action: :discard
    end

    resource QuickTrain.Accounts.AuthenticationEvent do
      define :record_authentication_event, action: :record, args: [:event, :result]
    end
  end
end
