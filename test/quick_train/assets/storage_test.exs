defmodule QuickTrain.Assets.StorageTest do
  use ExUnit.Case, async: false

  alias QuickTrain.Assets.Storage
  alias QuickTrain.Assets.Storage.Content
  alias QuickTrain.Assets.Storage.InMemory, as: TestStorage

  defmodule InvalidDescriptorStorage do
    def enforces_byte_cap?, do: true
    def writable_staging_access(_key, _cap, _expiry), do: :invalid
    def sealed_read_access(_key, _expiry), do: :invalid
  end

  defmodule UnenforcedStorage do
    def enforces_byte_cap?, do: false
    def approved_hosts, do: ["storage.quicktrain.local"]
  end

  defmodule OverlongStatelessStorage do
    @behaviour QuickTrain.Assets.Storage

    @impl true
    def enforces_byte_cap?, do: true

    @impl true
    def approved_hosts, do: ["storage.quicktrain.local"]

    @impl true
    def writable_staging_access(staging_key, byte_cap, expires_at) do
      {:ok, descriptor(:put, staging_key, DateTime.add(expires_at, 1, :second), byte_cap)}
    end

    @impl true
    def sealed_read_access(sealed_key, expires_at) do
      {:ok, descriptor(:get, sealed_key, DateTime.add(expires_at, 1, :second), nil)}
    end

    @impl true
    def verify_and_publish(_staging_key, _sealed_key, _expected, _deadline_ms),
      do: {:error, :unsupported}

    @impl true
    def verify_sealed(_sealed_key, _expected, _deadline_ms), do: {:error, :unsupported}

    defp descriptor(method, key, expires_at, byte_cap) do
      %{
        method: method,
        uri: URI.parse("https://storage.quicktrain.local/#{key}"),
        headers: [],
        expires_at: expires_at,
        cache_control: "no-store",
        referrer_policy: "no-referrer"
      }
      |> then(fn descriptor ->
        if byte_cap, do: Map.put(descriptor, :max_bytes, byte_cap), else: descriptor
      end)
    end
  end

  @png Base.decode64!(
         "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAAEElEQVR4nGP4z8AARAwoFABE0AX7pM/egAAAAABJRU5ErkJggg=="
       )

  setup do
    :ok = TestStorage.reset()
  end

  test "writable staging access enforces its byte cap and uses an approved HTTPS destination" do
    expires_at = DateTime.add(DateTime.utc_now(), 60, :second)

    assert {:ok, descriptor} =
             Storage.writable_staging_access("staging/one", 4, expires_at)

    assert descriptor.method == :put
    assert descriptor.uri.scheme == "https"
    assert descriptor.uri.host == "storage.quicktrain.local"
    assert descriptor.max_bytes == 4
    assert descriptor.cache_control == "no-store"
    assert descriptor.referrer_policy == "no-referrer"

    assert :ok = TestStorage.put_staging(descriptor, "four")
    assert {:error, :byte_cap_exceeded} = TestStorage.put_staging(descriptor, "fives")
  end

  test "an adapter without provider-enforced upload caps fails closed" do
    assets_config = Application.fetch_env!(:quick_train, :assets)

    Application.put_env(
      :quick_train,
      :assets,
      Keyword.put(assets_config, :storage_adapter, UnenforcedStorage)
    )

    on_exit(fn -> Application.put_env(:quick_train, :assets, assets_config) end)

    assert {:error, :byte_cap_not_enforced} =
             Storage.writable_staging_access(
               "staging/unsupported",
               4,
               DateTime.add(DateTime.utc_now(), 60, :second)
             )
  end

  test "verification pins staging, publishes only matching bytes, and reverifies sealed facts" do
    staging_key = "staging/image"
    sealed_key = "sealed/org/hash"
    expires_at = DateTime.add(DateTime.utc_now(), 60, :second)
    sha256 = :crypto.hash(:sha256, @png)

    descriptor = Storage.writable_staging_access!(staging_key, byte_size(@png), expires_at)
    :ok = TestStorage.put_staging(descriptor, @png)

    expected = %{sha256: sha256, byte_size: byte_size(@png), media_type: "image/png"}

    assert {:ok, result} =
             Storage.verify_and_publish(staging_key, sealed_key, expected, 1_000)

    assert result.sealed_key == sealed_key
    assert result.facts.media_type == "image/png"

    assert {:error, :staging_fenced} = TestStorage.put_staging(descriptor, "replacement")
    facts = result.facts
    assert {:ok, ^facts} = Storage.verify_sealed(sealed_key, expected, 1_000)

    assert {:ok, converged} =
             Storage.verify_and_publish(staging_key, sealed_key, expected, 1_000)

    assert converged.facts == result.facts
    assert TestStorage.sealed_count() == 1
  end

  test "publication returns a controlled error when its adapter deadline elapses" do
    staging_key = "staging/deadline"
    sealed_key = "sealed/deadline"
    content = "deadline-bound"
    expires_at = DateTime.add(DateTime.utc_now(), 60, :second)

    descriptor = Storage.writable_staging_access!(staging_key, byte_size(content), expires_at)
    :ok = TestStorage.put_staging(descriptor, content)
    :ok = TestStorage.set_publish_delay(75)

    expected = %{
      sha256: :crypto.hash(:sha256, content),
      byte_size: byte_size(content),
      media_type: "text/plain"
    }

    assert {:error, :storage_deadline_exceeded} =
             Storage.verify_and_publish(staging_key, sealed_key, expected, 10)
  end

  test "mismatched staging bytes never occupy the canonical key" do
    expires_at = DateTime.add(DateTime.utc_now(), 60, :second)
    descriptor = Storage.writable_staging_access!("staging/mismatch", 64, expires_at)
    :ok = TestStorage.put_staging(descriptor, "different")

    expected = %{
      sha256: <<0::256>>,
      byte_size: byte_size("different"),
      media_type: "text/plain"
    }

    assert {:error, :content_mismatch} =
             Storage.verify_and_publish(
               "staging/mismatch",
               "sealed/mismatch",
               expected,
               1_000
             )

    refute TestStorage.sealed?("sealed/mismatch")
  end

  test "opaque files preserve bytes without interpreting their declared media type" do
    for bytes <- ["<script>alert(1)</script>", "%PDF-1.7", "GIF89a", <<255, 216, 255>>, @png] do
      expected = %{
        sha256: :crypto.hash(:sha256, bytes),
        byte_size: byte_size(bytes),
        media_type: "text/plain"
      }

      assert {:ok, ^expected} = Content.verify(bytes, expected)
    end
  end

  test "malformed adapter returns produce controlled descriptor errors" do
    original_assets = Application.fetch_env!(:quick_train, :assets)
    on_exit(fn -> Application.put_env(:quick_train, :assets, original_assets) end)

    Application.put_env(
      :quick_train,
      :assets,
      Keyword.put(original_assets, :storage_adapter, InvalidDescriptorStorage)
    )

    expires_at = DateTime.add(DateTime.utc_now(), 60, :second)

    assert {:error, :invalid_storage_descriptor} =
             Storage.writable_staging_access("staging/invalid", 8, expires_at)

    assert {:error, :invalid_storage_descriptor} =
             Storage.sealed_read_access("sealed/invalid", expires_at)
  end

  test "defense-in-depth bounds reject oversized stored bytes" do
    original_assets = Application.fetch_env!(:quick_train, :assets)
    expires_at = DateTime.add(DateTime.utc_now(), 60, :second)

    on_exit(fn -> Application.put_env(:quick_train, :assets, original_assets) end)

    byte_descriptor = Storage.writable_staging_access!("staging/actual-size", 32, expires_at)
    bytes = String.duplicate("x", 32)
    :ok = TestStorage.put_staging(byte_descriptor, bytes)

    Application.put_env(
      :quick_train,
      :assets,
      Keyword.put(original_assets, :max_bytes, 16)
    )

    assert {:error, :content_mismatch} =
             Storage.verify_and_publish(
               "staging/actual-size",
               "sealed/actual-size",
               %{
                 sha256: :crypto.hash(:sha256, bytes),
                 byte_size: 32,
                 media_type: "text/plain"
               },
               1_000
             )

    refute TestStorage.sealed?("sealed/actual-size")
  end

  test "sealed reads are short-lived and use approved direct endpoints" do
    expires_at = DateTime.add(DateTime.utc_now(), 60, :second)
    descriptor = Storage.writable_staging_access!("staging/read", 8, expires_at)
    :ok = TestStorage.put_staging(descriptor, "readable")

    expected = %{
      sha256: :crypto.hash(:sha256, "readable"),
      byte_size: 8,
      media_type: "text/plain"
    }

    {:ok, _published} =
      Storage.verify_and_publish("staging/read", "sealed/read", expected, 1_000)

    read_expires_at = DateTime.add(DateTime.utc_now(), 30, :second)
    assert {:ok, read_descriptor} = Storage.sealed_read_access("sealed/read", read_expires_at)
    assert read_descriptor.method == :get
    assert read_descriptor.cache_control == "no-store"
    assert read_descriptor.referrer_policy == "no-referrer"
    assert {:ok, "readable"} = TestStorage.read_sealed(read_descriptor)

    assert read_descriptor.uri.scheme == "https"
    assert read_descriptor.uri.host in TestStorage.approved_hosts()
  end

  test "access descriptors cannot outlive the requested expiry" do
    original_assets = Application.fetch_env!(:quick_train, :assets)

    Application.put_env(
      :quick_train,
      :assets,
      Keyword.put(original_assets, :storage_adapter, OverlongStatelessStorage)
    )

    on_exit(fn -> Application.put_env(:quick_train, :assets, original_assets) end)

    expires_at = DateTime.add(DateTime.utc_now(), 60, :second)

    assert {:error, :storage_access_expiry_exceeded} =
             Storage.writable_staging_access("staging/overlong", 8, expires_at)

    assert {:error, :storage_access_expiry_exceeded} =
             Storage.sealed_read_access("sealed/overlong", expires_at)

    past = DateTime.add(DateTime.utc_now(), -60, :second)

    assert {:error, :storage_access_expired} =
             Storage.writable_staging_access("staging/expired", 8, past)

    assert {:error, :storage_access_expired} = Storage.sealed_read_access("sealed/expired", past)
  end

  test "a stateless storage adapter does not need to start a process" do
    original_assets = Application.fetch_env!(:quick_train, :assets)

    Application.put_env(
      :quick_train,
      :assets,
      Keyword.put(original_assets, :storage_adapter, OverlongStatelessStorage)
    )

    on_exit(fn -> Application.put_env(:quick_train, :assets, original_assets) end)

    assert :ignore = Storage.start_link([])
  end
end
