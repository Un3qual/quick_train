defmodule QuickTrain.Datasets.DatasetFieldCardinality do
  @moduledoc "Supported occurrence cardinalities for dataset fields."

  use Ash.Type.Enum, values: [:single]

  def graphql_type(_constraints), do: :dataset_field_cardinality
end
