defmodule QuickTrain.Accounts.Domain do
  @moduledoc false

  use Ash.Domain, otp_app: :quick_train, validate_config_inclusion?: false

  resources do
    resource QuickTrain.Accounts.User
    resource QuickTrain.Accounts.ExternalIdentity
    resource QuickTrain.Accounts.Session
    resource QuickTrain.Accounts.OidcLoginTransaction
    resource QuickTrain.Accounts.AuthenticationEvent
  end
end
