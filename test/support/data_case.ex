defmodule QuickTrain.DataCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      alias QuickTrain.Repo
    end
  end

  setup tags do
    owner = Sandbox.start_owner!(QuickTrain.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(owner) end)
    :ok
  end
end
