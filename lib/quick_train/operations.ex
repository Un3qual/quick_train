defmodule QuickTrain.Operations do
  @moduledoc "Idempotent operation correlation for user and system work."

  alias QuickTrain.Operations.Operation

  def start(attrs) do
    Operation
    |> Ash.Changeset.for_create(:start, attrs)
    |> Ash.create(authorize?: false)
  end
end
