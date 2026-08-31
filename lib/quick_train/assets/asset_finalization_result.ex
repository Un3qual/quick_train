defmodule QuickTrain.Assets.AssetFinalizationResult do
  @moduledoc "Typed terminal result for one asset registration."

  use Ash.Resource,
    otp_app: :quick_train,
    data_layer: :embedded,
    extensions: [AshGraphql.Resource]

  alias QuickTrain.Assets.AssetSummary

  attributes do
    attribute :asset, AssetSummary, allow_nil?: false, public?: true
    attribute :canonical_asset, AssetSummary, public?: true
  end

  graphql do
    type :asset_finalization_result
  end

  def from(asset, canonical_asset) do
    struct!(__MODULE__, %{
      asset: AssetSummary.from(asset),
      canonical_asset: canonical_asset && AssetSummary.from(canonical_asset)
    })
  end
end
