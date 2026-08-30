defmodule QuickTrain.Assets do
  @moduledoc "Immutable organization-owned asset content and storage lifecycle."

  use Ash.Domain, otp_app: :quick_train, extensions: [AshGraphql.Domain]

  resources do
    resource QuickTrain.Assets.Asset do
      define :register_asset,
        action: :register,
        args: [:organization_id, :sha256, :byte_size, :media_type]

      define :finalize_asset,
        action: :finalize,
        args: [:asset_id, :organization_id]

      define :get_asset_access,
        action: :access,
        args: [:asset_id, :organization_id]
    end
  end
end
