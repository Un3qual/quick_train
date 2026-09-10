defmodule QuickTrain.Forms.AssetIntendedUse do
  @moduledoc "Closed Forms intended use values."
  use Ash.Type.Enum, values: [:download, :image]
  def graphql_type(_constraints), do: :form_asset_intended_use
end
