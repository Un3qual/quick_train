defmodule QuickTrain.Assets.Workers.VerifyAsset do
  @moduledoc false

  use Oban.Worker,
    queue: :assets,
    max_attempts: 8,
    unique: [
      period: :infinity,
      fields: [:worker, :args],
      keys: [:asset_id],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias QuickTrain.{AshError, Assets}
  alias QuickTrain.Assets.Asset

  def enqueue(asset_id) do
    %{asset_id: asset_id}
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"asset_id" => asset_id}}) do
    case Ash.get(Asset, asset_id, authorize?: false, not_found_error?: false) do
      {:ok, nil} ->
        :ok

      {:ok, asset} ->
        case Assets.finalize_asset(asset.id, asset.organization_id, authorize?: false) do
          {:ok, _result} ->
            :ok

          {:error, error} ->
            verification_failure(error)
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp verification_failure(error) do
    if AshError.reason?(error, :asset_operation_in_progress),
      do: {:snooze, 10},
      else: {:error, error}
  end
end
