defmodule QuickTrain.Assets.AssetAccessResult do
  @moduledoc "Typed result of authorizing a short-lived sealed asset read."

  use Ash.Resource,
    otp_app: :quick_train,
    data_layer: :embedded,
    extensions: [AshGraphql.Resource]

  alias QuickTrain.Assets.{AssetSummary, StorageAccess}

  attributes do
    attribute :asset, AssetSummary, allow_nil?: false, public?: true
    attribute :read_access, StorageAccess, allow_nil?: false, public?: true
  end

  graphql do
    type :asset_access_result
  end

  def from(asset, read_access) do
    struct!(__MODULE__, %{
      asset: AssetSummary.from(asset),
      read_access: StorageAccess.from(read_access)
    })
  end
end
