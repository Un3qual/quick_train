defmodule QuickTrain.Datasets.DatasetImportRow.Outcome do
  @moduledoc "Processing outcome for one accepted dataset import row."

  use Ash.Type.Enum, values: [:pending, :succeeded, :unchanged, :failed]

  def graphql_type(_constraints), do: :dataset_import_row_outcome
end
