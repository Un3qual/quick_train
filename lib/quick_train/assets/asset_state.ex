defmodule QuickTrain.Assets.AssetState do
  @moduledoc "Lifecycle state for an immutable asset."

  use Ash.Type.Enum, values: [:pending, :ready, :failed, :duplicate_content]

  def storage_type, do: :asset_state
  def graphql_type(_constraints), do: :asset_state
end
