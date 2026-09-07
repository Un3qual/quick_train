defmodule QuickTrain.Assets.Storage.InMemory do
  @moduledoc "Deterministic in-memory storage for development and tests."

  @behaviour QuickTrain.Assets.Storage

  alias QuickTrain.Assets.Storage.{Content, MemoryStore}

  @store __MODULE__.Store
  @host "storage.quicktrain.local"

  @impl true
  def start_link(_opts), do: MemoryStore.start_link(name: @store, host: @host)
  def reset, do: MemoryStore.reset(@store)
  def set_publish_delay(delay_ms), do: MemoryStore.set_publish_delay(@store, delay_ms)
  def put_staging(descriptor, bytes), do: MemoryStore.put_staging(@store, descriptor, bytes)
  def read_sealed(descriptor), do: MemoryStore.read_sealed(@store, descriptor)
  def sealed?(key), do: MemoryStore.sealed?(@store, key)
  def staging?(key), do: MemoryStore.staging?(@store, key)
  def sealed_count, do: MemoryStore.sealed_count(@store)

  @impl true
  def enforces_byte_cap?, do: true
  @impl true
  def approved_hosts, do: [@host]
  @impl true
  def writable_staging_access(key, cap, expires_at),
    do: MemoryStore.issue_staging(@store, key, cap, expires_at)

  @impl true
  def sealed_read_access(sealed, expires_at),
    do: MemoryStore.issue_read(@store, sealed, expires_at)

  @impl true
  def verify_and_publish(staging_key, sealed_key, expected, deadline_ms)
      when is_integer(deadline_ms) and deadline_ms > 0 do
    deadline = deadline_after(deadline_ms)

    with {:ok, bytes} <-
           call_before(deadline, &MemoryStore.pin_staging(@store, staging_key, &1)),
         {:ok, facts} <- Content.verify(bytes, expected),
         {:ok, ^facts} <-
           call_before(deadline, &MemoryStore.publish(@store, sealed_key, bytes, facts, &1)),
         {:ok, ^facts} <-
           call_before(deadline, &MemoryStore.verify_sealed(@store, sealed_key, expected, &1)) do
      {:ok, %{sealed_key: sealed_key, facts: facts}}
    end
  end

  def verify_and_publish(_staging_key, _sealed_key, _expected, _deadline_ms),
    do: {:error, :invalid_publication_deadline}

  @impl true
  def verify_sealed(sealed_key, expected, deadline_ms)
      when is_integer(deadline_ms) and deadline_ms > 0 do
    deadline_ms
    |> deadline_after()
    |> call_before(&MemoryStore.verify_sealed(@store, sealed_key, expected, &1))
  end

  def verify_sealed(_sealed_key, _expected, _deadline_ms),
    do: {:error, :invalid_publication_deadline}

  @impl true
  def retire_staging(staging_key, not_before, deadline_ms)
      when is_integer(deadline_ms) and deadline_ms > 0 and is_struct(not_before, DateTime) do
    deadline_ms
    |> deadline_after()
    |> call_before(&MemoryStore.retire_staging(@store, staging_key, not_before, &1))
  end

  def retire_staging(_staging_key, _not_before, _deadline_ms),
    do: {:error, :invalid_retirement_deadline}

  defp deadline_after(deadline_ms),
    do: System.monotonic_time(:millisecond) + deadline_ms

  defp call_before(deadline, operation) do
    remaining_ms = deadline - System.monotonic_time(:millisecond)

    if remaining_ms > 0 do
      try do
        operation.(remaining_ms)
      catch
        :exit, {:timeout, _call} -> {:error, :storage_deadline_exceeded}
      end
    else
      {:error, :storage_deadline_exceeded}
    end
  end
end
