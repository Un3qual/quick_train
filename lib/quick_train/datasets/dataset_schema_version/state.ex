defmodule QuickTrain.Datasets.DatasetSchemaVersion.State do
  @moduledoc "Lifecycle state for a dataset schema version."

  use Ash.Type.Enum, values: [:draft, :published]

  def graphql_type(_constraints), do: :dataset_schema_state
end
