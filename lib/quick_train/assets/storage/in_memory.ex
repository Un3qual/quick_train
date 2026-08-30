defmodule QuickTrain.Assets.Storage.InMemory do
  @moduledoc false

  alias QuickTrain.Assets.Storage.{Content, MemoryStore}

  def verify_and_publish(server, staging_key, sealed_key, expected, deadline_ms)
      when is_integer(deadline_ms) and deadline_ms > 0 do
    with {:ok, bytes} <- MemoryStore.pin_staging(server, staging_key),
         {:ok, facts} <- Content.verify(bytes, expected),
         {:ok, ^facts} <- MemoryStore.publish(server, sealed_key, bytes, facts),
         {:ok, ^facts} <- MemoryStore.verify_sealed(server, sealed_key, expected) do
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
    MemoryStore.verify_sealed(server, sealed_key, expected)
  end

  def verify_sealed(_server, _sealed_key, _expected, _deadline_ms),
    do: {:error, :invalid_publication_deadline}

  def retire_staging(server, staging_key, not_before, deadline_ms)
      when is_integer(deadline_ms) and deadline_ms > 0 and is_struct(not_before, DateTime) do
    MemoryStore.retire_staging(server, staging_key, not_before)
  end

  def retire_staging(_server, _staging_key, _not_before, _deadline_ms),
    do: {:error, :invalid_retirement_deadline}
end
