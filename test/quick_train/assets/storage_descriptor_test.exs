defmodule QuickTrain.Assets.StorageDescriptorTest do
  use ExUnit.Case, async: false

  alias QuickTrain.Assets.{Storage, StorageAccess}

  defmodule DescriptorStorage do
    def enforces_byte_cap?, do: true
    def approved_hosts, do: ["storage.quicktrain.local"]
    def writable_staging_access(_key, _cap, _expiry), do: descriptor()
    def sealed_read_access(_key, _expiry), do: descriptor()

    defp descriptor,
      do: {:ok, Application.fetch_env!(:quick_train, :assets)[:test_descriptor]}
  end

  setup do
    config = Application.fetch_env!(:quick_train, :assets)
    on_exit(fn -> Application.put_env(:quick_train, :assets, config) end)

    Application.put_env(
      :quick_train,
      :assets,
      Keyword.put(config, :storage_adapter, DescriptorStorage)
    )

    expiry = DateTime.add(DateTime.utc_now(), 60, :second)

    descriptor = %{
      method: :post,
      uri: URI.parse("https://storage.quicktrain.local/bucket"),
      headers: [],
      form_fields: %{"key" => "staging/object", "policy" => "private-policy"},
      file_field: "file",
      max_bytes: 4,
      expires_at: expiry,
      cache_control: "no-store",
      referrer_policy: "no-referrer"
    }

    %{descriptor: descriptor, expiry: expiry}
  end

  test "POST access preserves exact form fields and redacts credentials when inspected", ctx do
    configure(ctx.descriptor)

    assert {:ok, descriptor} = Storage.writable_staging_access("staging/object", 4, ctx.expiry)
    assert descriptor.method == :post

    access = StorageAccess.from(descriptor)
    assert access.form_fields == %{"key" => "staging/object", "policy" => "private-policy"}
    assert access.file_field == "file"
    assert access.headers == %{}
    refute inspect(access) =~ "private-policy"
  end

  test "POST access rejects missing and malformed form data", ctx do
    malformed = [
      Map.delete(ctx.descriptor, :form_fields),
      Map.delete(ctx.descriptor, :file_field),
      %{ctx.descriptor | form_fields: nil},
      %{ctx.descriptor | form_fields: []},
      %{ctx.descriptor | form_fields: ctx.expiry},
      %{ctx.descriptor | form_fields: %{"policy" => 1}},
      %{ctx.descriptor | form_fields: %{"policy" => nil}},
      %{ctx.descriptor | form_fields: %{policy: "private-policy"}},
      %{ctx.descriptor | form_fields: %{"" => "private-policy"}},
      %{ctx.descriptor | form_fields: %{<<255>> => "private-policy"}},
      %{ctx.descriptor | form_fields: %{"policy" => <<255>>}},
      %{ctx.descriptor | form_fields: %{"file" => "already-populated"}},
      %{ctx.descriptor | file_field: nil},
      %{ctx.descriptor | file_field: ""},
      %{ctx.descriptor | file_field: <<255>>},
      %{ctx.descriptor | file_field: :file},
      %{ctx.descriptor | method: :delete},
      %{ctx.descriptor | headers: [{"authorization", 1}]}
    ]

    for descriptor <- malformed do
      configure(descriptor)

      assert {:error, :invalid_storage_descriptor} =
               Storage.writable_staging_access("staging/object", 4, ctx.expiry)
    end
  end

  test "POST access enforces HTTPS destination, expiry, and the requested byte cap", ctx do
    invalid = [
      {%{uri: URI.parse("http://storage.quicktrain.local/bucket")},
       :insecure_storage_destination},
      {%{uri: URI.parse("https://unapproved.example/bucket")}, :unapproved_storage_destination},
      {%{uri: URI.parse("https://storage.quicktrain.local:65536/bucket")},
       :unapproved_storage_destination},
      {%{uri: URI.parse("https://user@storage.quicktrain.local/bucket")},
       :unapproved_storage_destination},
      {%{uri: URI.parse("https://storage.quicktrain.local/bucket#fragment")},
       :unapproved_storage_destination},
      {%{uri: "https://storage.quicktrain.local/bucket"}, :invalid_storage_descriptor},
      {%{expires_at: DateTime.add(DateTime.utc_now(), -1, :second)}, :storage_access_expired},
      {%{expires_at: DateTime.add(ctx.expiry, 1, :second)}, :storage_access_expiry_exceeded},
      {%{expires_at: nil}, :invalid_storage_descriptor},
      {%{max_bytes: 5}, :byte_cap_not_enforced}
    ]

    for {attributes, reason} <- invalid do
      configure(Map.merge(ctx.descriptor, attributes))

      assert {:error, ^reason} =
               Storage.writable_staging_access("staging/object", 4, ctx.expiry)
    end
  end

  test "GET and PUT retain their representation and reject POST fields", ctx do
    for method <- [:get, :put] do
      descriptor =
        ctx.descriptor
        |> Map.put(:method, method)
        |> Map.drop([:form_fields, :file_field])
        |> then(fn descriptor ->
          if method == :get, do: Map.delete(descriptor, :max_bytes), else: descriptor
        end)

      configure(descriptor)
      assert {:ok, ^descriptor} = access(method, ctx.expiry)

      for fields <- [%{form_fields: %{}}, %{file_field: "file"}, %{form_fields: nil}] do
        configure(Map.merge(descriptor, fields))
        assert {:error, :invalid_storage_descriptor} = access(method, ctx.expiry)
      end
    end

    configure(ctx.descriptor |> Map.put(:method, :get) |> Map.drop([:form_fields, :file_field]))
    assert {:error, :invalid_storage_descriptor} = access(:get, ctx.expiry)
  end

  defp access(:get, expiry), do: Storage.sealed_read_access("sealed/object", expiry)
  defp access(:put, expiry), do: Storage.writable_staging_access("staging/object", 4, expiry)

  defp configure(descriptor) do
    config = Application.fetch_env!(:quick_train, :assets)
    Application.put_env(:quick_train, :assets, Keyword.put(config, :test_descriptor, descriptor))
  end
end
