defmodule QuickTrain.Projects.GroupIdentity do
  @moduledoc false
  def canonical(inputs) do
    encoded =
      inputs
      |> Enum.map(&{&1.input_slot_id, &1.project_item_id})
      |> Enum.sort()
      |> Enum.map(fn {slot, item} -> [frame(slot), frame(item)] end)
      |> then(&IO.iodata_to_binary([<<1>> | &1]))

    {:crypto.hash(:sha256, encoded), encoded}
  end

  defp frame(value), do: [<<byte_size(value)::unsigned-32>>, value]
end
