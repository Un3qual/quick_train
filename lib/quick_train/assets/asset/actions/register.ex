defmodule QuickTrain.Assets.Asset.Actions.Register do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  require Ash.Query

  alias QuickTrain.Assets.{Asset, AssetRegistrationResult, Storage}

  @impl true
  def run(input, _opts, _context) do
    arguments = input.arguments

    with :ok <- validate_declared_facts(arguments) do
      case ready_asset(arguments.organization_id, arguments.sha256) do
        nil -> create_pending(arguments)
        asset -> reuse_ready(asset, arguments)
      end
    end
  end

  defp validate_declared_facts(%{sha256: sha256, byte_size: byte_size, media_type: media_type}) do
    max_bytes = Application.fetch_env!(:quick_train, :assets)[:max_bytes]

    cond do
      not Regex.match?(~r/\A[0-9a-f]{64}\z/, sha256) -> {:error, :invalid_asset_hash}
      byte_size <= 0 -> {:error, :invalid_asset_size}
      byte_size > max_bytes -> {:error, :asset_too_large}
      String.trim(media_type) == "" -> {:error, :invalid_media_type}
      true -> :ok
    end
  end

  defp ready_asset(organization_id, sha256) do
    Asset
    |> Ash.Query.filter(
      organization_id == ^organization_id and sha256 == ^sha256 and state == :ready
    )
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
    asset_id = Ecto.UUID.generate()
    config = Application.fetch_env!(:quick_train, :assets)
    now = DateTime.utc_now()
    staging_expires_at = DateTime.add(now, config[:staging_lifetime_seconds], :second)
    staging_key = "assets/staging/#{arguments.organization_id}/#{asset_id}"

    attributes = %{
      id: asset_id,
      organization_id: arguments.organization_id,
      sha256: arguments.sha256,
      byte_size: arguments.byte_size,
      media_type: arguments.media_type,
      staging_key: staging_key,
      staging_expires_at: staging_expires_at
    }

    with {:ok, asset} <-
           Asset
           |> Ash.Changeset.for_create(:create_pending, attributes)
           |> Ash.create(authorize?: false),
         {:ok, access} <-
           Storage.writable_staging_access(
             staging_key,
             arguments.byte_size,
             access_expiry(now, staging_expires_at, config)
           ) do
      {:ok, AssetRegistrationResult.from(asset, access, false)}
    else
      {:error, error} ->
        discard_registration(asset_id)
        {:error, error}
    end
  end

  defp access_expiry(now, staging_expires_at, config) do
    requested = DateTime.add(now, config[:upload_access_lifetime_seconds], :second)
    if DateTime.before?(requested, staging_expires_at), do: requested, else: staging_expires_at
  end

  defp discard_registration(asset_id) do
    case Asset |> Ash.get(asset_id, authorize?: false) do
      {:ok, nil} -> :ok
      {:ok, asset} -> Ash.destroy(asset, action: :discard_registration, authorize?: false)
      {:error, _error} -> :ok
    end
  end
end
