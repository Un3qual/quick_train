defmodule QuickTrainWeb.GraphQL.Schema do
  @moduledoc "The single application API surface; extend this schema with product domains."

  use Absinthe.Schema

  query do
    field :health, non_null(:string) do
      resolve(fn _parent, _args, _resolution -> {:ok, "ok"} end)
    end
  end
end
