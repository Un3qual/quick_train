defmodule QuickTrain.ConnCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox
  alias Phoenix.ConnTest

  using do
    quote do
      @endpoint QuickTrainWeb.Endpoint
      import Plug.Conn
      import Phoenix.ConnTest
      import QuickTrain.DataCase, only: [organization_manager_fixture: 3]
      import QuickTrain.ConnCase, only: [graphql!: 2, graphql!: 3]
    end
  end

  setup tags do
    if tags[:committed_db] do
      if tags[:async], do: raise("committed database tests must run synchronously")
      :ok = Sandbox.checkout(QuickTrain.Repo, sandbox: false)

      on_exit(fn ->
        Sandbox.unboxed_run(QuickTrain.Repo, fn ->
          QuickTrain.Repo.query!("TRUNCATE users, organizations, capabilities, oban_jobs CASCADE")
        end)
      end)
    else
      owner = Sandbox.start_owner!(QuickTrain.Repo, shared: not tags[:async])
      on_exit(fn -> Sandbox.stop_owner(owner) end)
    end

    {:ok, conn: ConnTest.build_conn()}
  end

  def graphql!(conn, query, variables \\ %{}) do
    response =
      conn
      |> ConnTest.dispatch(QuickTrainWeb.Endpoint, :post, "/graphql", %{
        query: query,
        variables: variables
      })
      |> ConnTest.json_response(200)

    assert is_nil(response["errors"]), inspect(response["errors"])
    response["data"]
  end
end
