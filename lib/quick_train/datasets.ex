defmodule QuickTrain.Datasets do
  @moduledoc "Organization-owned normalized datasets, revisions, and imports."

  use Ash.Domain,
    otp_app: :quick_train

  resources do
    resource QuickTrain.Datasets.ProductCapabilities do
      define :grant_product_capabilities,
        action: :grant_to_manager,
        args: [:organization_id, :user_id]
    end
  end
end
