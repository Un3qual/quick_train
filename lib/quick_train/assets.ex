defmodule QuickTrain.Assets do
  @moduledoc "Immutable organization-owned asset content and storage lifecycle."

  use Ash.Domain, otp_app: :quick_train, extensions: [AshGraphql.Domain]

  resources do
    resource QuickTrain.Assets.Asset
  end
end
