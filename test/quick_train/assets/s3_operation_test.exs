defmodule QuickTrain.Assets.S3OperationTest do
  use ExUnit.Case, async: true
  alias QuickTrain.Assets.Storage.S3.Operation

  test "deadline cancels a blocked worker and removes its private spool" do
    parent = self()

    task =
      Task.async(fn ->
        Operation.run(100, fn directory, _deadline ->
          path = Path.join(directory, "content")
          File.write!(path, "incomplete")
          send(parent, {:spool, path, self()})
          Process.sleep(:infinity)
        end)
      end)

    assert_receive {:spool, path, worker}
    assert File.read!(path) == "incomplete"
    assert {:error, :storage_deadline_exceeded} = Task.await(task)
    refute Process.alive?(worker)
    refute File.exists?(Path.dirname(path))
  end
end
