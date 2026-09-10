defmodule QuickTrain.Assets.StorageAccess do
  @moduledoc "Opaque, short-lived storage access returned to an authorized caller."

  alias QuickTrain.Assets.StorageMethod

  use Ash.Resource,
    otp_app: :quick_train,
    data_layer: :embedded,
    extensions: [AshGraphql.Resource]

  attributes do
    attribute :method, StorageMethod, allow_nil?: false, public?: true
    attribute :uri, :string, allow_nil?: false, public?: true, sensitive?: true
    attribute :headers, :map, allow_nil?: false, public?: true, default: %{}
    attribute :expires_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :max_bytes, :integer, public?: true
    attribute :cache_control, :string, allow_nil?: false, public?: true
    attribute :referrer_policy, :string, allow_nil?: false, public?: true
  end

  graphql do
    type :asset_storage_access
  end

  def from(nil), do: nil

  def from(descriptor) do
    struct!(__MODULE__, %{
      method: descriptor.method,
      uri: URI.to_string(descriptor.uri),
      headers: Map.new(descriptor.headers),
      expires_at: descriptor.expires_at,
      max_bytes: Map.get(descriptor, :max_bytes),
      cache_control: descriptor.cache_control,
      referrer_policy: descriptor.referrer_policy
    })
  end
end
