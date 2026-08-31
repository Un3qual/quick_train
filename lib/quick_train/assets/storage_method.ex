defmodule QuickTrain.Assets.StorageMethod do
  @moduledoc "HTTP method for a short-lived asset storage descriptor."

  use Ash.Type.Enum, values: [:get, :put]

  def graphql_type(_constraints), do: :asset_storage_method
end
