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

  alias QuickTrain.Assets.Asset
  alias QuickTrain.Assets.Asset.Actions.Finalize

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
        case Finalize.finalize(Asset, asset.id, asset.organization_id) do
          {:ok, _result} -> :ok
          {:error, :asset_operation_in_progress} -> {:snooze, 10}
          {:error, error} -> {:error, error}
        end

      {:error, error} ->
        {:error, error}
    end
  end
end
