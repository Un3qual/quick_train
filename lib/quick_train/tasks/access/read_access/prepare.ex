defmodule QuickTrain.Tasks.Access.ReadAccess.Prepare do
  @moduledoc false
  use Ash.Resource.Preparation
  alias QuickTrain.Tasks.Access.ReadAccess
  require Ash.Query

  def prepare(query, opts, _context) do
    mode = Keyword.fetch!(opts, :mode)
    filter = ReadAccess.evidence_filter(query.resource, mode)

    query =
      query
      |> Ash.Query.filter(^filter)
      |> Ash.Query.set_context(%{shared: %{task_result_mode: mode}})

    case query.action.pagination do
      %{stable_sort: sort} when is_list(sort) ->
        query |> Ash.Query.sort(sort) |> Ash.Query.ensure_selected(Keyword.keys(sort))

      _ ->
        query
    end
  end
end
