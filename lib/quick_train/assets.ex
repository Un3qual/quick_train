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
      define :get_accessible_asset_internal,
        action: :resolve_ready_internal,
        args: [:asset_id, :organization_id],
        not_found_error?: false

      define :release_asset_claim,
        action: :release_unpublished_claim,
        get_by: [:id, :organization_id]

      define :start_asset_publication,
        action: :start_publication,
        get_by: [:id, :organization_id]

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
