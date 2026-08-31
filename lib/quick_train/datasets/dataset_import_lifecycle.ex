defmodule QuickTrain.Datasets.DatasetImportLifecycle do
  @moduledoc "Lifecycle derived from an import phase and its row outcomes."

  use Ash.Type.Enum, values: [:open, :pending, :completed, :failed, :partially_failed]

  def graphql_type(_constraints), do: :dataset_import_lifecycle
end
