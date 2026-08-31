defmodule QuickTrain.Datasets.DatasetImportRow.Outcome do
  @moduledoc "Processing outcome for one accepted dataset import row."

  use Ash.Type.Enum, values: [:pending, :succeeded, :unchanged, :failed]

  def storage_type, do: :dataset_import_row_outcome

  # PostgreSQL enums are already normalized; Ash's string-enum cast calls lower/1.
  defoverridable cast_atomic: 2

  @impl Ash.Type
  def cast_atomic(value, constraints) do
    if Ash.Expr.expr?(value), do: {:atomic, value}, else: super(value, constraints)
  end

  def graphql_type(_constraints), do: :dataset_import_row_outcome
end
