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
      define :issue_bearer_session, action: :issue_bearer, args: [:user_id]
      define :persist_bearer_session, action: :persist
      define :get_session_by_token_hash, action: :read, get_by: [:token_hash]
      define :revoke_session, action: :revoke
    end

    resource QuickTrain.Accounts.ExternalIdentity do
      define :create_external_identity, action: :create_identity
      define :get_external_identity, action: :read, get_by: [:issuer, :subject]
      define :refresh_external_identity, action: :refresh
    end

    resource QuickTrain.Accounts.OidcLoginTransaction do
      define :begin_oidc_login, action: :begin_login, args: [:callback_key, :network_source]
      define :store_oidc_login, action: :begin
      define :get_oidc_login, action: :read, get_by: [:state_hash]
      define :claim_oidc_login, action: :claim
      define :consume_oidc_login, action: :consume
      define :discard_oidc_login, action: :discard
    end

    resource QuickTrain.Accounts.AuthenticationEvent do
      define :record_authentication_event, action: :record, args: [:event, :result]
    end
  end
end
