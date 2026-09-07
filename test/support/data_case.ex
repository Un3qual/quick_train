defmodule QuickTrain.DataCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      alias QuickTrain.Repo
      import QuickTrain.DataCase, only: [concurrently: 1]
    end
  end

  setup tags do
    cond do
      tags[:committed_db] ->
        if tags[:async], do: raise("committed database tests must run synchronously")
        :ok = Sandbox.checkout(QuickTrain.Repo, sandbox: false)

        on_exit(fn ->
          Sandbox.unboxed_run(QuickTrain.Repo, fn ->
            # These synchronous tests own the dedicated test database between cases.
            QuickTrain.Repo.query!(
              "TRUNCATE users, organizations, capabilities, oban_jobs CASCADE"
            )
          end)
        end)

      tags[:unboxed_db] ->
        :ok

      true ->
        owner = Sandbox.start_owner!(QuickTrain.Repo, shared: not tags[:async])
        on_exit(fn -> Sandbox.stop_owner(owner) end)
    end

    :ok
  end

  def concurrently(operations) do
    parent = self()

    tasks =
      Enum.map(operations, fn operation ->
        Task.async(fn -> run_on_connection(parent, operation) end)
      end)

    try do
      backend_ids =
        Enum.map(tasks, fn task ->
          pid = task.pid
          assert_receive {:connection_ready, ^pid, backend_id}, 5_000
          backend_id
        end)

      assert length(Enum.uniq(backend_ids)) == length(tasks)
      Enum.each(tasks, &send(&1.pid, :go))
      Task.await_many(tasks, 15_000)
    after
      Enum.each(tasks, &Task.shutdown(&1, :brutal_kill))
    end
  end

  defp run_on_connection(parent, operation) do
    Sandbox.unboxed_run(QuickTrain.Repo, fn ->
      %{rows: [[backend_id]]} = QuickTrain.Repo.query!("SELECT pg_backend_pid()")
      send(parent, {:connection_ready, self(), backend_id})
      receive do: (:go -> operation.())
    end)
  end
end
