defmodule QuickTrain.Datasets.DatasetImportPhase do
  @moduledoc "Persisted acceptance phase for a dataset import."

  use Ash.Type.Enum, values: [:open, :sealed]

  def graphql_type(_constraints), do: :dataset_import_phase
end
