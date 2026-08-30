defmodule QuickTrain.Assets.AssetFinalizationResult do
  @moduledoc "Typed terminal result for one asset registration."

  use Ash.Resource,
    otp_app: :quick_train,
    data_layer: :embedded,
    extensions: [AshGraphql.Resource]

  attributes do
    attribute :asset, QuickTrain.Assets.AssetSummary, allow_nil?: false, public?: true
    attribute :canonical_asset, QuickTrain.Assets.AssetSummary, public?: true
  end

  graphql do
    type :asset_finalization_result
  end

  def from(asset, canonical_asset) do
    struct!(__MODULE__, %{
      asset: QuickTrain.Assets.AssetSummary.from(asset),
      canonical_asset: canonical_asset && QuickTrain.Assets.AssetSummary.from(canonical_asset)
    })
  end
end
