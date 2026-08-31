defmodule QuickTrain.Datasets.DatasetValueFamily do
  @moduledoc "Supported normalized value representations for dataset fields."

  use Ash.Type.Enum, values: [:text, :integer, :decimal, :boolean, :utc_datetime, :asset]

  def graphql_type(_constraints), do: :dataset_value_family
end
