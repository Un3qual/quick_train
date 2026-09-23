defmodule QuickTrain.Assets.Asset.Actions.Register do
  alias QuickTrain.Assets
  alias QuickTrain.Assets.Asset
  alias QuickTrain.Assets.AssetRegistrationResult
  alias QuickTrain.Assets.Ownership
  alias QuickTrain.Assets.Storage
  alias QuickTrain.DatasetAssetError
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  require Ash.Query

  @impl true
  def run(input, _opts, _context), do: DatasetAssetError.wrap(execute(input))

  defp execute(input) do
    arguments = input.arguments

    with {:ok, sha256} <- decode_hash(arguments.sha256),
         :ok <- validate_declared_facts(arguments) do
      arguments = %{arguments | sha256: sha256}

      case ready_asset(arguments.organization_id, arguments.sha256) do
        nil -> create_pending(arguments)
        asset -> reuse_ready(asset, arguments)
      end
    end
  end

  defp decode_hash(hash) when byte_size(hash) == 64 do
    case Base.decode16(hash, case: :lower) do
      {:ok, digest} -> {:ok, digest}
      :error -> {:error, :invalid_asset_hash}
    end
  end

  defp decode_hash(_hash), do: {:error, :invalid_asset_hash}

  defp validate_declared_facts(%{byte_size: byte_size, media_type: media_type}) do
    max_bytes = Keyword.fetch!(Application.fetch_env!(:quick_train, :assets), :max_bytes)

    cond do
      byte_size <= 0 ->
        {:error, :invalid_asset_size}

      byte_size > max_bytes ->
        {:error, :asset_too_large}

      not String.valid?(media_type) or String.contains?(media_type, <<0>>) or
          String.trim(media_type) == "" ->
        {:error, :invalid_media_type}

      true ->
        :ok
    end
  end

  defp ready_asset(organization_id, sha256) do
    Asset
    |> Ash.Query.filter(
      organization_id == ^organization_id and sha256 == ^sha256 and state == :ready
    )
    |> Ownership.independent_query()
    |> Ash.read_one!(authorize?: false)
  end

  defp reuse_ready(asset, %{byte_size: byte_size, media_type: media_type}) do
    if asset.byte_size == byte_size and asset.media_type == media_type do
      {:ok, AssetRegistrationResult.from(asset, nil, true)}
    else
      {:error, :asset_identity_conflict}
    end
  end

  defp create_pending(arguments) do
    changeset = Assets.changeset_to_create_pending_asset(arguments, authorize?: false)
    config = Application.fetch_env!(:quick_train, :assets)

    with {:ok, pending} <- Ash.Changeset.apply_attributes(changeset),
         {:ok, access} <-
           Storage.writable_staging_access(
             pending.staging_key,
             pending.byte_size,
             access_expiry(DateTime.utc_now(), pending.staging_expires_at, config)
           ),
         {:ok, asset} <- Ash.create(changeset, authorize?: false) do
      {:ok, AssetRegistrationResult.from(asset, access, false)}
    end
  end

  defp access_expiry(now, staging_expires_at, config) do
    requested =
      DateTime.add(now, Keyword.fetch!(config, :upload_access_lifetime_seconds), :second)

    if DateTime.before?(requested, staging_expires_at), do: requested, else: staging_expires_at
  end
end
