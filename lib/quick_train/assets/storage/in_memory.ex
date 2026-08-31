defmodule QuickTrain.Assets.Storage.InMemory do
  @moduledoc false

  alias QuickTrain.Assets.Storage.{Content, MemoryStore}

  def verify_and_publish(server, staging_key, sealed_key, expected, deadline_ms)
      when is_integer(deadline_ms) and deadline_ms > 0 do
    deadline = deadline_after(deadline_ms)

    with {:ok, bytes} <-
           call_before(deadline, &MemoryStore.pin_staging(server, staging_key, &1)),
         {:ok, facts} <- Content.verify(bytes, expected),
         {:ok, ^facts} <-
           call_before(deadline, &MemoryStore.publish(server, sealed_key, bytes, facts, &1)),
         {:ok, ^facts} <-
           call_before(deadline, &MemoryStore.verify_sealed(server, sealed_key, expected, &1)) do
      in_flight_seconds =
        :quick_train
        |> Application.fetch_env!(:assets)
        |> Keyword.fetch!(:provider_in_flight_seconds)

      {:ok,
       %{
         sealed_key: sealed_key,
         facts: facts,
         provider_in_flight_until: DateTime.add(DateTime.utc_now(), in_flight_seconds, :second)
       }}
    end
  end

  def verify_and_publish(_server, _staging_key, _sealed_key, _expected, _deadline_ms),
    do: {:error, :invalid_publication_deadline}

  def verify_sealed(server, sealed_key, expected, deadline_ms)
      when is_integer(deadline_ms) and deadline_ms > 0 do
    deadline_ms
    |> deadline_after()
    |> call_before(&MemoryStore.verify_sealed(server, sealed_key, expected, &1))
  end

  def verify_sealed(_server, _sealed_key, _expected, _deadline_ms),
    do: {:error, :invalid_publication_deadline}

  def retire_staging(server, staging_key, not_before, deadline_ms)
      when is_integer(deadline_ms) and deadline_ms > 0 and is_struct(not_before, DateTime) do
    deadline_ms
    |> deadline_after()
    |> call_before(&MemoryStore.retire_staging(server, staging_key, not_before, &1))
  end

  def retire_staging(_server, _staging_key, _not_before, _deadline_ms),
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
