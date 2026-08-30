defmodule QuickTrain.ConnCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      @endpoint QuickTrainWeb.Endpoint
      import Plug.Conn
      import Phoenix.ConnTest
    end
  end

  setup tags do
    owner = Sandbox.start_owner!(QuickTrain.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
