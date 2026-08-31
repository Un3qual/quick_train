defmodule QuickTrain.Assets.AssetSummary do
  @moduledoc "Public asset metadata without storage keys or operation claims."

  use Ash.Resource,
    otp_app: :quick_train,
    data_layer: :embedded,
    extensions: [AshGraphql.Resource]

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :state, QuickTrain.Assets.AssetState, allow_nil?: false, public?: true
    attribute :sha256, :string, allow_nil?: false, public?: true
    attribute :byte_size, :integer, allow_nil?: false, public?: true
    attribute :media_type, :string, allow_nil?: false, public?: true
    attribute :width, :integer, public?: true
    attribute :height, :integer, public?: true
    attribute :failure_reason, :string, public?: true
    attribute :canonical_asset_id, :uuid, public?: true
    attribute :staging_expires_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :staging_cleaned_at, :utc_datetime_usec, public?: true
  end

  graphql do
    type :asset_summary
  end

  def from(asset) do
    struct!(__MODULE__, Map.take(Map.from_struct(asset), public_fields()))
  end

  defp public_fields do
    [
      :id,
      :organization_id,
      :state,
      :sha256,
      :byte_size,
      :media_type,
      :width,
      :height,
      :failure_reason,
      :canonical_asset_id,
      :staging_expires_at,
      :staging_cleaned_at
    ]
  end
end
