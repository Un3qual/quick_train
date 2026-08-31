defmodule QuickTrain.Assets.AssetRegistrationResult do
  @moduledoc "Typed result of registering or exactly reusing an asset."

  use Ash.Resource,
    otp_app: :quick_train,
    data_layer: :embedded,
    extensions: [AshGraphql.Resource]

  alias QuickTrain.Assets.{AssetSummary, StorageAccess}

  attributes do
    attribute :asset, AssetSummary, allow_nil?: false, public?: true
    attribute :upload_access, StorageAccess, public?: true
    attribute :reused, :boolean, allow_nil?: false, public?: true
  end

  graphql do
    type :asset_registration_result
  end

  def from(asset, upload_access, reused?) do
    struct!(__MODULE__, %{
      asset: AssetSummary.from(asset),
      upload_access: StorageAccess.from(upload_access),
      reused: reused?
    })
  end
end
