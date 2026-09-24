defmodule QuickTrain.AshError do
  @moduledoc false

  def constraint?(error, constraint_names) do
    any_error?(error, fn leaf_error ->
      case constraint_name(leaf_error) do
        nil -> false
        constraint_name -> constraint_name in constraint_names
      end
    end)
  end

  def reason?(error, reason) do
    any_error?(error, fn
      %{category: ^reason} -> true
      _error -> false
    end)
  end

  defp any_error?(%{errors: errors}, predicate), do: any_error?(errors, predicate)

  defp any_error?(errors, predicate) when is_list(errors),
    do: Enum.any?(errors, &any_error?(&1, predicate))

  defp any_error?(error, predicate), do: predicate.(error)

  defp constraint_name(%{private_vars: private_vars}) when is_list(private_vars) do
    Keyword.get(private_vars, :constraint)
  end

  defp constraint_name(%{private_vars: private_vars}) when is_map(private_vars) do
    Map.get(private_vars, :constraint)
  end

  defp constraint_name(%{constraint: constraint}), do: constraint
  defp constraint_name(_error), do: nil
end
