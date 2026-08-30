defmodule QuickTrain.Assets.Workers.AssetStagingCleanup do
  @moduledoc false

  use Oban.Worker,
    queue: :assets,
    max_attempts: 5,
    unique: [
      period: :infinity,
      fields: [:worker],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias QuickTrain.Assets.Asset
  alias QuickTrain.Assets.Asset.Cleanup

  @page_size 100

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    now = DateTime.utc_now()

    with {:ok, assets} <- Cleanup.expired_assets(Asset, now, @page_size) do
      errors =
        Enum.reduce(assets, [], fn asset, errors ->
          case Cleanup.cleanup(Asset, asset.id, now) do
            {:ok, _status} -> errors
            {:error, error} -> [error | errors]
          end
        end)

      case errors do
        [] -> :ok
        errors -> {:error, {:asset_staging_cleanup_failed, length(errors)}}
      end
    end
  end
end
