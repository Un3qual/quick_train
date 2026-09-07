defmodule QuickTrain.Assets.AssetSummary do
  @moduledoc "Public asset metadata without storage keys or operation claims."

  alias Ash.Resource.Info
  alias QuickTrain.Assets.AssetState

  use Ash.Resource,
    otp_app: :quick_train,
    data_layer: :embedded,
    extensions: [AshGraphql.Resource]

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :state, AssetState, allow_nil?: false, public?: true
    attribute :sha256, :binary, allow_nil?: false, public?: true
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
    attribute_types sha256: :string
    attribute_input_types sha256: :string
    type :asset_summary
  end

  def from(asset) do
    fields = __MODULE__ |> Info.attribute_names() |> MapSet.to_list()
    struct!(__MODULE__, Map.take(Map.from_struct(asset), fields))
  end
end
