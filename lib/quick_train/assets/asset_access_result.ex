defmodule QuickTrain.Assets.AssetAccessResult do
  @moduledoc "Typed result of authorizing a short-lived sealed asset read."

  use Ash.Resource,
    otp_app: :quick_train,
    data_layer: :embedded,
    extensions: [AshGraphql.Resource]

  attributes do
    attribute :asset, QuickTrain.Assets.AssetSummary, allow_nil?: false, public?: true
    attribute :read_access, QuickTrain.Assets.StorageAccess, allow_nil?: false, public?: true
  end

  graphql do
    type :asset_access_result
  end

  def from(asset, read_access) do
    struct!(__MODULE__, %{
      asset: QuickTrain.Assets.AssetSummary.from(asset),
      read_access: QuickTrain.Assets.StorageAccess.from(read_access)
    })
  end
end
