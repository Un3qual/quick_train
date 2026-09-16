defmodule QuickTrain.Assets.StreamingStorageTest do
  use ExUnit.Case, async: false

  alias QuickTrain.Assets.Storage
  alias QuickTrain.Assets.Storage.InMemory

  defmodule ClientUploadStorage do
    defdelegate enforces_byte_cap?(), to: InMemory
    defdelegate approved_hosts(), to: InMemory
    defdelegate writable_staging_access(key, cap, expiry), to: InMemory
  end

  defmodule FailingStorage do
    def enforces_byte_cap?, do: true

    def write_staging("staging/unavailable", _chunks, _cap, _deadline),
      do: {:error, :export_storage_unavailable}

    def write_staging(_key, _chunks, _cap, _deadline), do: {:error, "private provider credential"}
  end

  defmodule UncappedStorage do
    def enforces_byte_cap?, do: false
    def write_staging(_key, _chunks, _cap, _deadline), do: raise("write must not be called")
  end

  setup do
    config = Application.fetch_env!(:quick_train, :assets)
    on_exit(fn -> Application.put_env(:quick_train, :assets, config) end)
    :ok = InMemory.reset()
    :ok
  end

  test "streamed chunks enter the existing immutable hash and size sealing protocol" do
    chunks = Stream.map(["one", "\n", "two\n"], & &1)
    expected = expected("one\ntwo\n")

    assert :ok = Storage.write_staging("staging/stream", chunks, 8, 1_000)
    refute InMemory.sealed?("sealed/stream")

    assert {:ok, %{sealed_key: "sealed/stream", facts: ^expected}} =
             Storage.verify_and_publish("staging/stream", "sealed/stream", expected, 1_000)

    assert {:ok, descriptor} =
             Storage.sealed_read_access("sealed/stream", DateTime.add(DateTime.utc_now(), 60))

    assert {:ok, "one\ntwo\n"} = InMemory.read_sealed(descriptor)

    assert {:error, :staging_fenced} =
             Storage.write_staging("staging/stream", ["replacement"], 11, 1_000)

    assert {:ok, "one\ntwo\n"} = InMemory.read_sealed(descriptor)
    assert {:ok, ^expected} = Storage.verify_sealed("sealed/stream", expected, 1_000)
  end

  test "a stream stops at the byte cap without leaving publishable partial content" do
    owner = self()

    chunks =
      Stream.map(["four", "!", "unread"], fn chunk ->
        send(owner, {:consumed, chunk})
        chunk
      end)

    assert {:error, :byte_cap_exceeded} =
             Storage.write_staging("staging/capped", chunks, 4, 1_000)

    assert_received {:consumed, "four"}
    assert_received {:consumed, "!"}
    refute_received {:consumed, "unread"}

    assert {:error, :staging_missing} =
             Storage.verify_and_publish(
               "staging/capped",
               "sealed/capped",
               expected("four"),
               1_000
             )

    assert {:error, :sealed_missing} =
             Storage.sealed_read_access("sealed/capped", DateTime.add(DateTime.utc_now(), 60))
  end

  test "an interrupted source returns a sanitized failure without staging partial content" do
    chunks =
      Stream.map(["first", "second"], fn
        "first" -> "first"
        "second" -> raise "private source payload"
      end)

    assert {:error, :storage_write_failed} =
             Storage.write_staging("staging/interrupted", chunks, 16, 1_000)

    assert {:error, :staging_missing} =
             Storage.verify_and_publish(
               "staging/interrupted",
               "sealed/interrupted",
               expected("first"),
               1_000
             )
  end

  test "server writes unavailable on a client-only adapter leave client uploads working" do
    configure(ClientUploadStorage)
    chunks = Stream.map(["unused"], fn _chunk -> flunk("unavailable storage read the source") end)

    assert {:error, :export_storage_unavailable} =
             Storage.write_staging("staging/unsupported", chunks, 8, 1_000)

    assert {:ok, descriptor} =
             Storage.writable_staging_access(
               "staging/client",
               4,
               DateTime.add(DateTime.utc_now(), 60)
             )

    assert :ok = InMemory.put_staging(descriptor, "four")

    configure(nil)

    assert {:error, :export_storage_unavailable} =
             Storage.write_staging("staging/unconfigured", chunks, 8, 1_000)
  end

  test "provider error details are not exposed" do
    configure(FailingStorage)

    assert {:error, :storage_write_failed} =
             Storage.write_staging("staging/provider-error", ["four"], 4, 1_000)
  end

  test "an adapter can explicitly report unavailable server writes" do
    configure(FailingStorage)

    assert {:error, :export_storage_unavailable} =
             Storage.write_staging("staging/unavailable", ["four"], 4, 1_000)
  end

  test "an adapter that cannot enforce the byte cap never receives generated content" do
    configure(UncappedStorage)

    assert {:error, :byte_cap_not_enforced} =
             Storage.write_staging("staging/uncapped", ["four"], 4, 1_000)
  end

  test "a blocking stream times out without installing partial staging bytes" do
    owner = self()

    chunks =
      Stream.map(["first", "second"], fn chunk ->
        send(owner, {:consumed, chunk, self()})
        if chunk == "second", do: Process.sleep(5_000)
        chunk
      end)

    started = System.monotonic_time(:millisecond)

    assert {:error, :storage_deadline_exceeded} =
             Storage.write_staging("staging/timeout", chunks, 32, 25)

    assert System.monotonic_time(:millisecond) - started < 1_000
    assert_received {:consumed, "second", enumerator}
    refute Process.alive?(enumerator)

    assert {:error, :staging_missing} =
             Storage.verify_and_publish(
               "staging/timeout",
               "sealed/timeout",
               expected("first"),
               1_000
             )
  end

  test "a timed-out queued staging write cannot commit after the server resumes" do
    :sys.suspend(InMemory)

    try do
      assert {:error, :storage_deadline_exceeded} =
               Storage.write_staging("staging/queued", ["four"], 4, 25)
    after
      :sys.resume(InMemory)
    end

    assert {:error, :staging_missing} =
             Storage.verify_and_publish(
               "staging/queued",
               "sealed/queued",
               expected("four"),
               1_000
             )
  end

  defp expected(bytes),
    do: %{
      sha256: :crypto.hash(:sha256, bytes),
      byte_size: byte_size(bytes),
      media_type: "application/jsonl"
    }

  defp configure(adapter) do
    config = Application.fetch_env!(:quick_train, :assets)
    Application.put_env(:quick_train, :assets, Keyword.put(config, :storage_adapter, adapter))
  end
end
