defmodule QuickTrain.Datasets.DatasetRevisionResult do
  @moduledoc "Changed or unchanged result from canonical item-revision construction."

  @enforce_keys [:changed, :item, :revision]
  defstruct [:changed, :item, :revision]
end
