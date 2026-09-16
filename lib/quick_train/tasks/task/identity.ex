defmodule QuickTrain.Tasks.Task.Identity do
  @moduledoc false
  def key(inputs) do
    encoded =
      inputs
      |> Enum.map(&{&1.input_slot_id, &1.revision_id})
      |> Enum.sort()
      |> :erlang.term_to_binary()

    :crypto.hash(:sha256, encoded)
  end
end
