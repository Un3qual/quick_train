defmodule QuickTrain.Assets.StorageTest do
  use ExUnit.Case, async: false

  alias QuickTrain.Assets.Storage
  alias QuickTrain.Assets.Storage.Test, as: TestStorage

  defmodule UnenforcedStorage do
    def enforces_byte_cap?, do: false
    def approved_hosts, do: ["storage.quicktrain.test"]
  end

  @png <<
    137,
    80,
    78,
    71,
    13,
    10,
    26,
    10,
    0,
    0,
    0,
    13,
    73,
    72,
    68,
    82,
    0,
    0,
    0,
    2,
    0,
    0,
    0,
    3,
    8,
    2,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    73,
    69,
    78,
    68,
    0,
    0,
    0,
    0
  >>

  setup do
    :ok = TestStorage.reset()
  end

  test "writable staging access enforces its byte cap and uses an approved HTTPS destination" do
    expires_at = DateTime.add(DateTime.utc_now(), 60, :second)

    assert {:ok, descriptor} =
             Storage.writable_staging_access("staging/one", 4, expires_at)

    assert descriptor.method == :put
    assert descriptor.uri.scheme == "https"
    assert descriptor.uri.host == "storage.quicktrain.test"
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
    sha256 = Base.encode16(:crypto.hash(:sha256, @png), case: :lower)

    descriptor = Storage.writable_staging_access!(staging_key, byte_size(@png), expires_at)
    :ok = TestStorage.put_staging(descriptor, @png)

    expected = %{sha256: sha256, byte_size: byte_size(@png), media_type: "image/png"}

    assert {:ok, result} =
             Storage.verify_and_publish(staging_key, sealed_key, expected, 1_000)

    assert result.sealed_key == sealed_key
    assert result.facts.width == 2
    assert result.facts.height == 3
    assert result.facts.media_type == "image/png"
    assert DateTime.after?(result.provider_in_flight_until, DateTime.utc_now())

    assert {:error, :staging_fenced} = TestStorage.put_staging(descriptor, "replacement")
    facts = result.facts
    assert {:ok, ^facts} = Storage.verify_sealed(sealed_key, expected, 1_000)

    assert {:ok, converged} =
             Storage.verify_and_publish(staging_key, sealed_key, expected, 1_000)

    assert converged.facts == result.facts
    assert TestStorage.sealed_count() == 1
  end

  test "mismatched or active staging bytes never occupy the canonical key" do
    expires_at = DateTime.add(DateTime.utc_now(), 60, :second)
    descriptor = Storage.writable_staging_access!("staging/mismatch", 64, expires_at)
    :ok = TestStorage.put_staging(descriptor, "different")

    expected = %{
      sha256: String.duplicate("0", 64),
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

    html = "<!doctype html><html><body>active</body></html>"
    active_descriptor = Storage.writable_staging_access!("staging/active", 128, expires_at)
    :ok = TestStorage.put_staging(active_descriptor, html)

    active_expected = %{
      sha256: Base.encode16(:crypto.hash(:sha256, html), case: :lower),
      byte_size: byte_size(html),
      media_type: "text/plain"
    }

    assert {:error, :active_content_rejected} =
             Storage.verify_and_publish(
               "staging/active",
               "sealed/active",
               active_expected,
               1_000
             )

    refute TestStorage.sealed?("sealed/active")
  end

  test "sealed reads are short-lived and redirects fail closed" do
    expires_at = DateTime.add(DateTime.utc_now(), 60, :second)
    descriptor = Storage.writable_staging_access!("staging/read", 8, expires_at)
    :ok = TestStorage.put_staging(descriptor, "readable")

    expected = %{
      sha256: Base.encode16(:crypto.hash(:sha256, "readable"), case: :lower),
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

    assert :ok = Storage.validate_redirect(read_descriptor, read_descriptor.uri)

    assert {:error, :insecure_storage_destination} =
             Storage.validate_redirect(
               read_descriptor,
               URI.parse("http://storage.quicktrain.test/x")
             )

    assert {:error, :unapproved_storage_destination} =
             Storage.validate_redirect(read_descriptor, URI.parse("https://attacker.example/x"))
  end

  test "retirement fences expired upload descriptors before deletion completes" do
    now = DateTime.utc_now()
    descriptor = Storage.writable_staging_access!("staging/retire", 8, now)

    assert :ok = Storage.retire_staging("staging/retire", now, 1_000)
    assert {:error, :staging_retired} = TestStorage.put_staging(descriptor, "late")
    refute TestStorage.staging?("staging/retire")
  end
end
