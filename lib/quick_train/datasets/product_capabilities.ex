defmodule QuickTrain.Datasets.ProductCapabilities do
  @moduledoc "Product-owned bootstrap actions for the normalized datasets and assets capabilities."

  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Datasets

  actions do
    action :grant_to_manager, {:array, :string} do
      allow_nil? false

      argument :organization_id, :uuid, allow_nil?: false
      argument :user_id, :uuid, allow_nil?: false

      run QuickTrain.Datasets.ProductCapabilities.Actions.GrantToManager
    end
  end
end
