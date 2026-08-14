defmodule QuickTrain.Organizations.Domain do
  @moduledoc false

  use Ash.Domain, otp_app: :quick_train, validate_config_inclusion?: false

  resources do
    resource QuickTrain.Organizations.Organization
    resource QuickTrain.Organizations.Membership
  end
end
