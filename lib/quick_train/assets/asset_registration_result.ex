defmodule QuickTrain.Assets.AssetRegistrationResult do
  @moduledoc "Typed result of registering or exactly reusing an asset."

  use Ash.Resource,
    otp_app: :quick_train,
    data_layer: :embedded,
    extensions: [AshGraphql.Resource]

  attributes do
    attribute :asset, QuickTrain.Assets.AssetSummary, allow_nil?: false, public?: true
    attribute :upload_access, QuickTrain.Assets.StorageAccess, public?: true
    attribute :reused, :boolean, allow_nil?: false, public?: true
  end

  graphql do
    type :asset_registration_result
  end

  def from(asset, upload_access, reused?) do
    struct!(__MODULE__, %{
      asset: QuickTrain.Assets.AssetSummary.from(asset),
      upload_access: QuickTrain.Assets.StorageAccess.from(upload_access),
      reused: reused?
    })
  end
end
