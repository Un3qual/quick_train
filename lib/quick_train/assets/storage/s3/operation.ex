defmodule QuickTrain.Assets.Storage.S3.Operation do
  @moduledoc false

  # The caller owns the private directory and removes it even when the worker
  # blocks in enumeration or is killed during a request. Remote writes may still finish.
  def run(budget, fun) when is_integer(budget) and budget > 0 do
    safely(fn -> execute(budget, fun) end)
  end

  def run(_budget, _fun), do: {:error, :storage_deadline_exceeded}

  defp execute(budget, fun) do
    deadline = System.monotonic_time(:millisecond) + budget
    directory = Path.join(System.tmp_dir!(), "quicktrain-storage-#{Ash.UUID.generate()}")
    File.mkdir!(directory)

    try do
      File.chmod!(directory, 0o700)
      task = Task.async(fn -> safely(fn -> fun.(directory, deadline) end) end)

      case Task.yield(task, max(deadline - System.monotonic_time(:millisecond), 0)) do
        {:ok, result} ->
          result

        nil ->
          Task.shutdown(task, :brutal_kill)
          {:error, :storage_deadline_exceeded}
      end
    after
      File.rm_rf!(directory)
    end
  end

  def remaining(deadline) do
    case deadline - System.monotonic_time(:millisecond) do
      remaining when remaining > 0 -> remaining
      _expired -> throw({:storage_error, :storage_deadline_exceeded})
    end
  end

  defp safely(fun) do
    fun.()
  rescue
    # reach:disable-next-line bare_rescue -- Never expose stream, filesystem, or provider secrets.
    _exception -> {:error, :storage_write_failed}
  catch
    {:storage_error, reason} -> {:error, reason}
    _kind, _reason -> {:error, :storage_write_failed}
  end
end
