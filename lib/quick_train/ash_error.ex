defmodule QuickTrain.AshError do
  @moduledoc false

  def constraint?(error, constraint_names) do
    constraint_names = MapSet.new(constraint_names)

    Enum.any?(leaf_errors(error), fn leaf_error ->
      case constraint_name(leaf_error) do
        nil -> false
        constraint_name -> MapSet.member?(constraint_names, constraint_name)
      end
    end)
  end

  def reason?(error, reason) do
    Enum.any?(leaf_errors(error), fn
      %{category: ^reason} -> true
      _error -> false
    end)
  end

  defp leaf_errors(error) do
    error
    |> Ash.Error.traverse_errors(& &1)
    |> flatten_traversal()
  end

  defp flatten_traversal(%_{} = leaf_error), do: [leaf_error]

  defp flatten_traversal(map) when is_map(map) do
    map
    |> Map.values()
    |> Enum.flat_map(&flatten_traversal/1)
  end

  defp flatten_traversal(list) when is_list(list), do: Enum.flat_map(list, &flatten_traversal/1)
  defp flatten_traversal(_other), do: []

  defp constraint_name(%{private_vars: private_vars}) when is_list(private_vars) do
    Keyword.get(private_vars, :constraint)
  end

  defp constraint_name(%{private_vars: private_vars}) when is_map(private_vars) do
    Map.get(private_vars, :constraint)
  end

  defp constraint_name(%{constraint: constraint}), do: constraint
  defp constraint_name(_error), do: nil
end
