defmodule QuickTrain.Tasks.TaskSelectionTest do
  use ExUnit.Case, async: true

  alias QuickTrain.Tasks.TaskSelection

  test "canonical identity preserves slot membership but ignores input presentation" do
    first = [
      %{input_slot_id: "a", project_item_id: "1"},
      %{input_slot_id: "b", project_item_id: "2"}
    ]

    swapped = [
      %{input_slot_id: "b", project_item_id: "1"},
      %{input_slot_id: "a", project_item_id: "2"}
    ]

    assert TaskSelection.canonical(first) == TaskSelection.canonical(Enum.reverse(first))
    refute TaskSelection.canonical(first) == TaskSelection.canonical(swapped)
  end

  test "balanced groups anchor on unmet coverage, allow covered companions, and use distinct items" do
    slots = [%{input_slot_id: "slot", item_count: 2}]
    items = [%{id: "1", coverage: 0}, %{id: "2", coverage: 4}, %{id: "3", coverage: 1}]
    [group | _] = TaskSelection.balanced_groups(slots, items, 1) |> Enum.to_list()
    assert Enum.sort(Enum.map(group, & &1.project_item_id)) == ["1", "3"]
    assert [_, _] = Enum.uniq_by(group, & &1.project_item_id)
  end

  test "balanced search can pass an already issued preferred group without inventing a schedule" do
    slots = [%{input_slot_id: "slot", item_count: 2}]
    items = [%{id: "1", coverage: 0}, %{id: "2", coverage: 1}, %{id: "3", coverage: 2}]
    groups = TaskSelection.balanced_groups(slots, items, 1) |> Enum.to_list()

    assert Enum.map(groups, fn group -> Enum.sort(Enum.map(group, & &1.project_item_id)) end) == [
             ["1", "2"],
             ["1", "3"]
           ]

    assert TaskSelection.balanced_groups(slots, Enum.map(items, &%{&1 | coverage: 2}), 1)
           |> Enum.to_list() == []
  end
end
