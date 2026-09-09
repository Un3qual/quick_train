defmodule QuickTrain.Datasets.DatasetAssetCapabilities do
  @moduledoc "Grants dataset and asset capabilities to an existing organization manager."

  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Datasets

  actions do
    action :grant_to_manager, {:array, :string} do
      allow_nil? false

      argument :organization_id, :uuid, allow_nil?: false
      argument :user_id, :uuid, allow_nil?: false

      run QuickTrain.Datasets.DatasetAssetCapabilities.Actions.GrantToManager
    end
  end
end
