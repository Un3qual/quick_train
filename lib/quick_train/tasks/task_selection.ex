defmodule QuickTrain.Tasks.TaskSelection do
  @moduledoc false

  defdelegate canonical(inputs), to: QuickTrain.Projects.GroupIdentity

  def balanced_groups(slots, items, coverage_target) do
    ordered = items |> Enum.shuffle() |> Enum.sort_by(& &1.coverage)

    ordered
    |> Stream.filter(&(&1.coverage < coverage_target))
    |> Stream.flat_map(fn anchor ->
      Stream.flat_map(slots, fn anchor_slot ->
        groups(
          slots,
          Enum.reject(ordered, &(&1.id == anchor.id)),
          anchor,
          anchor_slot.input_slot_id
        )
      end)
    end)
    |> Stream.uniq_by(&canonical/1)
  end

  defp groups([], _remaining, _anchor, _anchor_slot), do: [[]]

  defp groups([slot | rest], remaining, anchor, anchor_slot) do
    anchored? = slot.input_slot_id == anchor_slot
    count = slot.item_count - if(anchored?, do: 1, else: 0)

    remaining
    |> combinations(count)
    |> Stream.flat_map(fn chosen ->
      chosen_ids = MapSet.new(chosen, & &1.id)
      next = Enum.reject(remaining, &MapSet.member?(chosen_ids, &1.id))
      selected = if anchored?, do: [anchor | chosen], else: chosen
      inputs = Enum.map(selected, &%{input_slot_id: slot.input_slot_id, project_item_id: &1.id})
      Stream.map(groups(rest, next, anchor, anchor_slot), &(inputs ++ &1))
    end)
  end

  defp combinations(_items, 0), do: [[]]
  defp combinations([], _count), do: []

  defp combinations([item | rest], count) when count > 0 do
    Stream.concat(
      Stream.map(combinations(rest, count - 1), &[item | &1]),
      Stream.flat_map([rest], &combinations(&1, count))
    )
  end
end
