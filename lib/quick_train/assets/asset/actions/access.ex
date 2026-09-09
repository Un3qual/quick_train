defmodule QuickTrain.Assets.Asset.Actions.Access do
  @moduledoc false

  alias QuickTrain.DatasetAssetError

  use Ash.Resource.Actions.Implementation

  alias QuickTrain.Assets
  alias QuickTrain.Assets.{AssetAccessResult, Storage}

  @impl true
  def run(input, _opts, _context), do: DatasetAssetError.wrap(execute(input))

  defp execute(input) do
    %{asset_id: asset_id, organization_id: organization_id} = input.arguments

    with {:ok, asset} <- accessible_asset(asset_id, organization_id),
         {:ok, access} <- Storage.sealed_read_access(asset.sealed_key, read_expiry()) do
      {:ok, AssetAccessResult.from(asset, access)}
    end
  end

  defp accessible_asset(asset_id, organization_id) do
    case Assets.get_accessible_asset_internal(asset_id, organization_id, authorize?: false) do
      {:ok, nil} -> {:error, :asset_not_ready}
      {:ok, asset} -> {:ok, asset}
      {:error, error} -> {:error, error}
    end
  end

  defp read_expiry do
    lifetime =
      Keyword.fetch!(Application.fetch_env!(:quick_train, :assets), :read_access_lifetime_seconds)

    DateTime.add(DateTime.utc_now(), lifetime, :second)
  end
end
