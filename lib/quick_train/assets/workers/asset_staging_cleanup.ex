defmodule QuickTrain.Assets.Workers.AssetStagingCleanup do
  # The bounded cleanup scan deliberately fails fast on its first resource error.
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting
  @moduledoc false

  use Oban.Worker,
    queue: :assets,
    max_attempts: 5,
    unique: [
      period: :infinity,
      fields: [:worker],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias QuickTrain.Assets

  @page_size 100

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    now = DateTime.utc_now()

    cutoff =
      DateTime.add(
        now,
        -Application.fetch_env!(:quick_train, :assets)[:cleanup_grace_seconds],
        :second
      )

    with {:ok, assets} <-
           Assets.list_expired_staging_assets(cutoff,
             query: [limit: @page_size],
             authorize?: false
           ) do
      errors =
        Enum.reduce(assets, [], fn asset, errors ->
          case Assets.cleanup_asset_staging(asset.id, %{now: now}, authorize?: false) do
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
