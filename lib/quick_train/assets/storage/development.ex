defmodule QuickTrain.Assets.Storage.Development do
  @moduledoc "Deterministic in-memory development adapter for local asset workflows."

  @behaviour QuickTrain.Assets.Storage

  alias QuickTrain.Assets.Storage.{InMemory, MemoryStore}

  @store __MODULE__.Store
  @host "storage.quicktrain.local"

  @impl true
  def start_link(_opts), do: MemoryStore.start_link(name: @store, host: @host)
  @impl true
  def enforces_byte_cap?, do: true
  @impl true
  def approved_hosts, do: [@host]
  @impl true
  def writable_staging_access(key, cap, expires_at),
    do: MemoryStore.issue_staging(@store, key, cap, expires_at)

  @impl true
  def verify_and_publish(staging, sealed, expected, deadline),
    do: InMemory.verify_and_publish(@store, staging, sealed, expected, deadline)

  @impl true
  def verify_sealed(sealed, expected, deadline),
    do: InMemory.verify_sealed(@store, sealed, expected, deadline)

  @impl true
  def retire_staging(staging, not_before, deadline),
    do: InMemory.retire_staging(@store, staging, not_before, deadline)

  @impl true
  def sealed_read_access(sealed, expires_at),
    do: MemoryStore.issue_read(@store, sealed, expires_at)
end
