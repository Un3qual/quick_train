defmodule QuickTrain.Assets.Asset.Actions.Access do
  @moduledoc false

  alias QuickTrain.ProductError

  use Ash.Resource.Actions.Implementation

  require Ash.Query

  alias QuickTrain.Assets.{Asset, AssetAccessResult, Storage}

  @impl true
  def run(input, _opts, _context), do: ProductError.wrap(execute(input))

  defp execute(input) do
    %{asset_id: asset_id, organization_id: organization_id} = input.arguments

    with {:ok, asset} <- accessible_asset(asset_id, organization_id),
         {:ok, access} <- Storage.sealed_read_access(asset.sealed_key, read_expiry()) do
      {:ok, AssetAccessResult.from(asset, access)}
    end
  end

  defp accessible_asset(asset_id, organization_id) do
    asset =
      Asset
      |> Ash.Query.filter(id == ^asset_id and organization_id == ^organization_id)
      |> Ash.read_one!(authorize?: false)

    case asset do
      %{state: :ready} = asset ->
        {:ok, asset}

      %{state: :duplicate_content, canonical_asset_id: canonical_asset_id} ->
        canonical =
          Asset
          |> Ash.Query.filter(
            id == ^canonical_asset_id and organization_id == ^organization_id and state == :ready
          )
          |> Ash.read_one!(authorize?: false)

        if canonical, do: {:ok, canonical}, else: {:error, :asset_not_ready}

      _asset ->
        {:error, :asset_not_ready}
    end
  end

  defp read_expiry do
    lifetime = Application.fetch_env!(:quick_train, :assets)[:read_access_lifetime_seconds]
    DateTime.add(DateTime.utc_now(), lifetime, :second)
  end
end
