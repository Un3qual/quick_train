defmodule QuickTrain.Assets do
  @moduledoc "Immutable organization-owned asset content and storage lifecycle."

  use Ash.Domain, otp_app: :quick_train, extensions: [AshGraphql.Domain]

  alias QuickTrain.Assets.Asset

  graphql do
    queries do
      read_one Asset, :asset, :get_scoped
      action Asset, :asset_access, :access
    end

    mutations do
      action Asset, :register_asset, :register,
        args: [:organization_id, :sha256, :byte_size, :media_type]

      action Asset, :finalize_asset, :finalize, args: [:asset_id, :organization_id]
    end
  end

  resources do
    resource Asset do
      define :cleanup_asset_staging, action: :cleanup_staging, args: [:asset_id]
      define :list_expired_staging_assets, action: :expired_staging, args: [:cutoff]

      define :reconcile_asset_publication,
        action: :reconcile_publication,
        args: [:asset_id, :organization_id, :claim_id, :sealed_key, :facts]

      define :register_asset,
        action: :register,
        args: [:organization_id, :sha256, :byte_size, :media_type]

      define :finalize_asset,
        action: :finalize,
        args: [:asset_id, :organization_id]

      define :get_asset_access,
        action: :access,
        args: [:asset_id, :organization_id]

      define :get_asset, action: :get_scoped, args: [:asset_id, :organization_id]
    end
  end
end
