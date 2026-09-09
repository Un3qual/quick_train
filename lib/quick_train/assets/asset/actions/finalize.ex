defmodule QuickTrain.Assets.Asset.Actions.Finalize do
  # Claim fencing is an explicit storage/database state machine with bounded branches.
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting
  # credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity
  @moduledoc false

  alias QuickTrain.DatasetAssetError

  use Ash.Resource.Actions.Implementation

  require Ash.Query

  alias QuickTrain.AshError
  alias QuickTrain.Assets.{Asset, AssetFinalizationResult, Storage}

  @terminal_storage_errors [
    :content_mismatch,
    :active_content_rejected,
    :unsupported_media_type,
    :image_bounds_exceeded
  ]
  @commit_attempts 2

  @impl true
  def run(%{action: %{name: :reconcile_publication}, arguments: args}, _opts, _context) do
    DatasetAssetError.wrap(
      commit_success(
        args.asset_id,
        args.organization_id,
        args.claim_id,
        args.sealed_key,
        args.facts
      )
    )
  end

  def run(input, _opts, _context) do
    %{asset_id: asset_id, organization_id: organization_id} = input.arguments
    DatasetAssetError.wrap(finalize(asset_id, organization_id))
  end

  defp finalize(asset_id, organization_id) do
    claim_id = Ecto.UUID.generate()

    case acquire_claim(asset_id, organization_id, claim_id) do
      {:ok, {:terminal, asset}} -> result(asset)
      {:ok, {:claimed, asset}} -> reconcile_or_publish(asset, claim_id)
      {:ok, :busy} -> {:error, :asset_operation_in_progress}
      {:ok, :missing} -> {:error, :asset_not_found}
      {:error, error} -> {:error, error}
    end
  end

  defp acquire_claim(asset_id, organization_id, claim_id) do
    now = DateTime.utc_now()
    claim_expires_at = DateTime.add(now, config(:operation_claim_seconds), :second)

    Ash.transact(Asset, fn ->
      asset = locked_asset(asset_id, organization_id)

      cond do
        is_nil(asset) ->
          :missing

        asset.state != :pending ->
          {:terminal, asset}

        live_claim?(asset, now) ->
          :busy

        DateTime.compare(asset.staging_expires_at, now) != :gt ->
          asset = complete_failed!(asset, "staging_expired")
          {:terminal, asset}

        true ->
          asset =
            asset
            |> Ash.Changeset.for_update(:claim_operation, %{
              operation_claim_kind: :finalize,
              operation_claim_id: claim_id,
              operation_claim_expires_at: claim_expires_at
            })
            |> Ash.update!(authorize?: false)

          {:claimed, asset}
      end
    end)
  end

  defp reconcile_or_publish(asset, claim_id) do
    sealed_key = sealed_key(asset)
    expected = expected_facts(asset)
    deadline_ms = config(:publication_deadline_ms)

    case Storage.verify_sealed(sealed_key, expected, deadline_ms) do
      {:ok, facts} ->
        commit_success(asset.id, asset.organization_id, claim_id, sealed_key, facts)

      {:error, :sealed_missing} ->
        publish(asset, claim_id, sealed_key, expected, deadline_ms)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp publish(asset, claim_id, sealed_key, expected, deadline_ms) do
    with {:ok, :started} <- start_publication(asset.id, asset.organization_id, claim_id) do
      case Storage.verify_and_publish(
             asset.staging_key,
             sealed_key,
             expected,
             deadline_ms
           ) do
        {:ok, %{facts: facts}} ->
          commit_success(asset.id, asset.organization_id, claim_id, sealed_key, facts)

        {:error, reason} when reason in @terminal_storage_errors ->
          commit_failure(asset.id, asset.organization_id, claim_id, reason)

        {:error, reason} when reason in [:staging_missing, :staging_retired] ->
          _result = release_unpublished_claim(asset.id, asset.organization_id, claim_id)
          {:error, reason}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp release_unpublished_claim(asset_id, organization_id, claim_id) do
    Ash.transact(Asset, fn ->
      asset = locked_asset(asset_id, organization_id)

      if asset && asset.state == :pending && asset.operation_claim_id == claim_id do
        asset
        |> Ash.Changeset.for_update(:release_unpublished_claim, %{})
        |> Ash.update!(authorize?: false)
      end

      :ok
    end)
  end

  defp start_publication(asset_id, organization_id, claim_id) do
    now = DateTime.utc_now()
    claim_expires_at = DateTime.add(now, config(:operation_claim_seconds), :second)
    publication_may_finish_at = DateTime.add(now, config(:provider_in_flight_seconds), :second)

    Ash.transact(Asset, fn ->
      asset = locked_asset(asset_id, organization_id)

      if current_claim?(asset, claim_id, now) do
        asset
        |> Ash.Changeset.for_update(:start_publication, %{
          operation_claim_expires_at: claim_expires_at,
          publication_may_finish_at: publication_may_finish_at
        })
        |> Ash.update!(authorize?: false)

        :started
      else
        :stale
      end
    end)
    |> case do
      {:ok, :started} -> {:ok, :started}
      {:ok, :stale} -> {:error, :stale_asset_claim}
      {:error, error} -> {:error, error}
    end
  end

  defp commit_success(asset_id, organization_id, claim_id, sealed_key, facts) do
    commit_success(
      asset_id,
      organization_id,
      claim_id,
      sealed_key,
      facts,
      @commit_attempts
    )
  end

  defp commit_success(
         asset_id,
         organization_id,
         claim_id,
         sealed_key,
         facts,
         attempts
       ) do
    result =
      Ash.transact(Asset, fn ->
        asset = locked_asset(asset_id, organization_id)

        cond do
          is_nil(asset) ->
            :missing

          asset.state != :pending ->
            {:terminal, asset}

          not live_claim_identity?(asset, claim_id, DateTime.utc_now()) ->
            :stale

          true ->
            case ready_asset(asset) do
              nil ->
                ready =
                  asset
                  |> Ash.Changeset.for_update(:complete_ready, %{
                    sealed_key: sealed_key,
                    width: Map.get(facts, :width),
                    height: Map.get(facts, :height)
                  })
                  |> Ash.update!(authorize?: false)

                {:terminal, ready}

              canonical ->
                duplicate =
                  asset
                  |> Ash.Changeset.for_update(:complete_duplicate, %{
                    canonical_asset_id: canonical.id
                  })
                  |> Ash.update!(authorize?: false)

                {:terminal, duplicate}
            end
        end
      end)

    case result do
      {:ok, {:terminal, asset}} ->
        result(asset)

      {:ok, :stale} ->
        {:error, :stale_asset_claim}

      {:ok, :missing} ->
        {:error, :asset_not_found}

      {:error, error} when attempts > 1 ->
        if ready_uniqueness_conflict?(error) do
          commit_success(
            asset_id,
            organization_id,
            claim_id,
            sealed_key,
            facts,
            attempts - 1
          )
        else
          {:error, error}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp commit_failure(asset_id, organization_id, claim_id, reason) do
    sanitized_reason = sanitize_failure(reason)

    Ash.transact(Asset, fn ->
      asset = locked_asset(asset_id, organization_id)

      cond do
        is_nil(asset) -> :missing
        asset.state != :pending -> {:terminal, asset}
        not live_claim_identity?(asset, claim_id, DateTime.utc_now()) -> :stale
        true -> {:terminal, complete_failed!(asset, sanitized_reason)}
      end
    end)
    |> case do
      {:ok, {:terminal, asset}} -> result(asset)
      {:ok, :stale} -> {:error, :stale_asset_claim}
      {:ok, :missing} -> {:error, :asset_not_found}
      {:error, error} -> {:error, error}
    end
  end

  defp complete_failed!(asset, reason) do
    asset
    |> Ash.Changeset.for_update(:complete_failed, %{failure_reason: reason})
    |> Ash.update!(authorize?: false)
  end

  defp ready_asset(asset) do
    Asset
    |> Ash.Query.filter(
      organization_id == ^asset.organization_id and sha256 == ^asset.sha256 and state == :ready
    )
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(authorize?: false)
  end

  defp locked_asset(asset_id, organization_id) do
    Asset
    |> Ash.Query.filter(id == ^asset_id and organization_id == ^organization_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(authorize?: false)
  end

  defp result(%{state: :duplicate_content} = asset) do
    canonical = Asset |> Ash.get!(asset.canonical_asset_id, authorize?: false)
    {:ok, AssetFinalizationResult.from(asset, canonical)}
  end

  defp result(%{state: :ready} = asset),
    do: {:ok, AssetFinalizationResult.from(asset, asset)}

  defp result(asset), do: {:ok, AssetFinalizationResult.from(asset, nil)}

  defp expected_facts(asset) do
    %{sha256: asset.sha256, byte_size: asset.byte_size, media_type: asset.media_type}
  end

  defp sealed_key(asset),
    do: "assets/sealed/#{asset.organization_id}/#{Base.encode16(asset.sha256, case: :lower)}"

  defp live_claim?(%{operation_claim_id: nil}, _now), do: false

  defp live_claim?(%{operation_claim_expires_at: expires_at}, now),
    do: DateTime.compare(expires_at, now) == :gt

  defp current_claim?(nil, _claim_id, _now), do: false

  defp current_claim?(asset, claim_id, now) do
    asset.state == :pending and asset.operation_claim_kind == :finalize and
      asset.operation_claim_id == claim_id and live_claim?(asset, now)
  end

  defp live_claim_identity?(asset, claim_id, now) do
    asset.state == :pending and asset.operation_claim_id == claim_id and live_claim?(asset, now)
  end

  defp sanitize_failure(:content_mismatch), do: "content_mismatch"
  defp sanitize_failure(:active_content_rejected), do: "active_content_rejected"
  defp sanitize_failure(:unsupported_media_type), do: "unsupported_media_type"
  defp sanitize_failure(:image_bounds_exceeded), do: "image_bounds_exceeded"

  defp ready_uniqueness_conflict?(error) do
    AshError.constraint?(error, [
      "assets_ready_organization_sha256_index",
      "assets_sealed_key_index"
    ])
  end

  defp config(key), do: Application.fetch_env!(:quick_train, :assets)[key]
end
