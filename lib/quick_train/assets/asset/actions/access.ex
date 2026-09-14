defmodule QuickTrain.Assets.Asset.Actions.Access do
  alias QuickTrain.Assets
  alias QuickTrain.Assets.AssetAccessResult
  alias QuickTrain.Assets.Ownership
  alias QuickTrain.Assets.Storage
  alias QuickTrain.DatasetAssetError
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  @impl true
  def run(input, _opts, context), do: DatasetAssetError.wrap(execute(input, context))

  defp execute(input, context) do
    %{asset_id: asset_id, organization_id: organization_id} = input.arguments

    with {:ok, asset} <- accessible_asset(asset_id, organization_id),
         :ok <- Ownership.require_independent(asset.id, context),
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
