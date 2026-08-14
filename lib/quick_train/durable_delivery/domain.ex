defmodule QuickTrain.DurableDelivery.Domain do
  @moduledoc false
  use Ash.Domain, otp_app: :quick_train, validate_config_inclusion?: false

  resources do
    resource QuickTrain.DurableDelivery.DomainEvent
  end
end
