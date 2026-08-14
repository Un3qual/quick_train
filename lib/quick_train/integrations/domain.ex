defmodule QuickTrain.Integrations.Domain do
  @moduledoc false
  use Ash.Domain, otp_app: :quick_train, validate_config_inclusion?: false

  resources do
    resource QuickTrain.Integrations.WebhookReceipt
    resource QuickTrain.Integrations.IntegrationCredential
    resource QuickTrain.Integrations.ExternalReference
  end
end
