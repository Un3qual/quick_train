defmodule QuickTrain.Assets.Asset.Cleanup do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  require Ash.Query

  alias QuickTrain.{Assets, DatasetAssetError}
  alias QuickTrain.Assets.Asset
  alias QuickTrain.Assets.Storage

  @impl true
  def run(input, _opts, _context) do
    DatasetAssetError.wrap(cleanup(input.arguments.asset_id, input.arguments.now))
  end

  defp cleanup(asset_id, now) do
    claim_id = Ecto.UUID.generate()

    case acquire_claim(asset_id, claim_id, now) do
      {:ok, {:claimed, asset}} -> reconcile_or_retire(asset, claim_id, now)
      {:ok, status} when status in [:missing, :ineligible, :busy] -> {:ok, status}
      {:error, error} -> {:error, error}
    end
  end

  defp acquire_claim(asset_id, claim_id, now) do
    expires_at = DateTime.add(now, config(:operation_claim_seconds), :second)

    Ash.transact(Asset, fn ->
      asset = locked_asset(asset_id)

      cond do
        is_nil(asset) ->
          :missing

        not eligible?(asset, now) ->
          :ineligible

        live_claim?(asset, now) ->
          :busy

        true ->
          claimed =
            asset
            |> Ash.Changeset.for_update(:claim_cleanup, %{
              operation_claim_kind: :cleanup,
              operation_claim_id: claim_id,
              operation_claim_expires_at: expires_at
            })
            |> Ash.update!(authorize?: false)

          {:claimed, claimed}
      end
    end)
  end

  defp reconcile_or_retire(asset, claim_id, now) do
    sealed_key =
      "assets/sealed/#{asset.organization_id}/#{Base.encode16(asset.sha256, case: :lower)}"

    expected = %{sha256: asset.sha256, byte_size: asset.byte_size, media_type: asset.media_type}

    case Storage.verify_sealed(sealed_key, expected, config(:publication_deadline_ms)) do
      {:ok, facts} when asset.state == :pending ->
        with {:ok, _result} <-
               Assets.reconcile_asset_publication(
                 asset.id,
                 asset.organization_id,
                 claim_id,
                 sealed_key,
                 facts,
                 authorize?: false
               ) do
          cleanup(asset.id, now)
        end

      {:ok, _facts} when asset.state in [:ready, :duplicate_content] ->
        retire(asset, claim_id, now)

      {:ok, _facts} when asset.state == :failed ->
        if canonical_accounted?(asset) do
          retire(asset, claim_id, now)
        else
          {:error, :unaccounted_canonical_object}
        end

      {:error, :sealed_missing} ->
        if publication_window_open?(asset, now) do
          release_for_retry(asset.id, claim_id, :waiting_for_publication)
        else
          retire(asset, claim_id, now)
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp retire(asset, claim_id, now) do
    not_before = retirement_not_before(asset)

    case Storage.retire_staging(
           asset.staging_key,
           not_before,
           config(:publication_deadline_ms)
         ) do
      :ok ->
        complete_cleanup(asset.id, claim_id, now)

      {:error, :staging_access_still_active} ->
        release_for_retry(asset.id, claim_id, :waiting_for_access_expiry)

      {:error, error} ->
        {:error, error}
    end
  end

  defp release_for_retry(asset_id, claim_id, status) do
    Ash.transact(Asset, fn ->
      asset = locked_asset(asset_id)

      if asset && asset.operation_claim_kind == :cleanup &&
           asset.operation_claim_id == claim_id do
        asset
        |> Ash.Changeset.for_update(:release_operation_claim, %{})
        |> Ash.update!(authorize?: false)
      end

      status
    end)
    |> case do
      {:ok, ^status} -> {:ok, status}
      {:error, error} -> {:error, error}
    end
  end

  defp complete_cleanup(asset_id, claim_id, now) do
    Ash.transact(Asset, fn ->
      asset = locked_asset(asset_id)

      cond do
        is_nil(asset) ->
          :missing

        not current_cleanup_claim?(asset, claim_id, DateTime.utc_now()) ->
          :stale

        asset.state == :pending ->
          asset
          |> Ash.Changeset.for_update(:complete_expired_staging_cleanup, %{
            staging_cleaned_at: now
          })
          |> Ash.update!(authorize?: false)

          :cleaned

        true ->
          asset
          |> Ash.Changeset.for_update(:complete_staging_cleanup, %{staging_cleaned_at: now})
          |> Ash.update!(authorize?: false)

          :cleaned
      end
    end)
    |> case do
      {:ok, status} when status in [:cleaned, :missing] -> {:ok, status}
      {:ok, :stale} -> {:error, :stale_asset_claim}
      {:error, error} -> {:error, error}
    end
  end

  defp canonical_accounted?(asset) do
    Asset
    |> Ash.Query.filter(
      organization_id == ^asset.organization_id and sha256 == ^asset.sha256 and state == :ready
    )
    |> Ash.exists?(authorize?: false)
  end

  defp locked_asset(asset_id) do
    Asset
    |> Ash.Query.filter(id == ^asset_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(authorize?: false)
  end

  defp eligible?(asset, now) do
    cutoff = DateTime.add(now, -config(:cleanup_grace_seconds), :second)

    is_nil(asset.staging_cleaned_at) and
      DateTime.compare(asset.staging_expires_at, cutoff) != :gt and
      asset.state in [:pending, :failed, :duplicate_content, :ready]
  end

  defp live_claim?(%{operation_claim_id: nil}, _now), do: false

  defp live_claim?(%{operation_claim_expires_at: expires_at}, now),
    do: DateTime.compare(expires_at, now) == :gt

  defp current_cleanup_claim?(asset, claim_id, now) do
    asset.operation_claim_kind == :cleanup and asset.operation_claim_id == claim_id and
      live_claim?(asset, now)
  end

  defp publication_window_open?(%{publication_may_finish_at: nil}, _now), do: false

  defp publication_window_open?(asset, now),
    do: DateTime.compare(asset.publication_may_finish_at, now) == :gt

  defp retirement_not_before(asset) do
    cleanup_not_before =
      DateTime.add(asset.staging_expires_at, config(:cleanup_grace_seconds), :second)

    case asset.publication_may_finish_at do
      nil ->
        cleanup_not_before

      publication_end ->
        Enum.max_by([cleanup_not_before, publication_end], &DateTime.to_unix(&1, :microsecond))
    end
  end

  defp config(key), do: Application.fetch_env!(:quick_train, :assets)[key]
end
