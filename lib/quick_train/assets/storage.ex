defmodule QuickTrain.Assets.Storage do
  @moduledoc """
  Provider-neutral storage contract for immutable organization assets.

  Upload and read descriptors must target direct endpoints that cannot redirect.
  Adapters must enforce this through their provider configuration; clients receive
  descriptors directly, so this module cannot intercept later HTTP redirects.
  A provider that cannot meet this requirement is not a supported adapter.
  """

  @type object_key :: String.t()
  @type deadline_ms :: pos_integer()

  @type access_descriptor :: %{
          required(:method) => :get | :put,
          required(:uri) => URI.t(),
          required(:headers) => [{String.t(), String.t()}],
          required(:expires_at) => DateTime.t(),
          required(:cache_control) => String.t(),
          required(:referrer_policy) => String.t(),
          optional(:max_bytes) => pos_integer()
        }

  @type expected_facts :: %{
          required(:sha256) => <<_::256>>,
          required(:byte_size) => pos_integer(),
          required(:media_type) => String.t()
        }

  @type verified_facts :: %{
          required(:sha256) => <<_::256>>,
          required(:byte_size) => pos_integer(),
          required(:media_type) => String.t(),
          optional(:width) => pos_integer(),
          optional(:height) => pos_integer()
        }

  @type publish_result :: %{
          required(:sealed_key) => object_key(),
          required(:facts) => verified_facts()
        }

  @callback enforces_byte_cap?() :: boolean()
  @callback approved_hosts() :: [String.t()]

  @callback start_link(keyword()) :: GenServer.on_start() | :ignore

  @optional_callbacks start_link: 1

  @callback writable_staging_access(
              staging_key :: object_key(),
              byte_cap :: pos_integer(),
              expires_at :: DateTime.t()
            ) :: {:ok, access_descriptor()} | {:error, term()}

  @callback verify_and_publish(
              staging_key :: object_key(),
              sealed_key :: object_key(),
              expected :: expected_facts(),
              deadline_ms()
            ) :: {:ok, publish_result()} | {:error, term()}

  @callback verify_sealed(
              sealed_key :: object_key(),
              expected :: expected_facts(),
              deadline_ms()
            ) :: {:ok, verified_facts()} | {:error, term()}

  @callback sealed_read_access(
              sealed_key :: object_key(),
              expires_at :: DateTime.t()
            ) :: {:ok, access_descriptor()} | {:error, term()}

  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [[]]},
      type: :worker
    }
  end

  def start_link(_opts) do
    case adapter() do
      nil ->
        :ignore

      adapter ->
        start_adapter(adapter)
    end
  end

  def adapter do
    :quick_train
    |> Application.get_env(:assets, [])
    |> Keyword.get(:storage_adapter)
  end

  def writable_staging_access(staging_key, byte_cap, expires_at) do
    with {:ok, adapter} <- configured_adapter(),
         true <- adapter.enforces_byte_cap?() || {:error, :byte_cap_not_enforced},
         {:ok, descriptor} <- adapter.writable_staging_access(staging_key, byte_cap, expires_at),
         :ok <- validate_descriptor(descriptor, :put, adapter, byte_cap, expires_at) do
      {:ok, descriptor}
    else
      {:error, _reason} = error -> error
      _invalid -> {:error, :invalid_storage_descriptor}
    end
  end

  def writable_staging_access!(staging_key, byte_cap, expires_at) do
    case writable_staging_access(staging_key, byte_cap, expires_at) do
      {:ok, descriptor} -> descriptor
      {:error, reason} -> raise "storage access failed: #{inspect(reason)}"
    end
  end

  def verify_and_publish(staging_key, sealed_key, expected, deadline_ms) do
    with {:ok, adapter} <- configured_adapter() do
      adapter.verify_and_publish(staging_key, sealed_key, expected, deadline_ms)
    end
  end

  def verify_sealed(sealed_key, expected, deadline_ms) do
    with {:ok, adapter} <- configured_adapter() do
      adapter.verify_sealed(sealed_key, expected, deadline_ms)
    end
  end

  def sealed_read_access(sealed_key, expires_at) do
    with {:ok, adapter} <- configured_adapter(),
         {:ok, descriptor} <- adapter.sealed_read_access(sealed_key, expires_at),
         :ok <- validate_descriptor(descriptor, :get, adapter, nil, expires_at) do
      {:ok, descriptor}
    else
      {:error, _reason} = error -> error
      _invalid -> {:error, :invalid_storage_descriptor}
    end
  end

  defp configured_adapter do
    case adapter() do
      nil -> {:error, :storage_not_configured}
      adapter -> {:ok, adapter}
    end
  end

  defp start_adapter(adapter) do
    case Code.ensure_loaded(adapter) do
      {:module, ^adapter} -> start_loaded_adapter(adapter)
      {:error, reason} -> {:error, {:storage_adapter_unavailable, adapter, reason}}
    end
  end

  defp start_loaded_adapter(adapter) do
    if function_exported?(adapter, :start_link, 1), do: adapter.start_link([]), else: :ignore
  end

  defp validate_descriptor(descriptor, method, adapter, byte_cap, requested_expires_at)
       when is_map(descriptor) do
    with ^method <- Map.get(descriptor, :method),
         %URI{} = uri <- Map.get(descriptor, :uri),
         :ok <- validate_destination(uri, adapter),
         %DateTime{} = descriptor_expires_at <- Map.get(descriptor, :expires_at),
         :ok <- validate_expiry(descriptor_expires_at, requested_expires_at),
         "no-store" <- Map.get(descriptor, :cache_control),
         "no-referrer" <- Map.get(descriptor, :referrer_policy),
         headers when is_list(headers) <- Map.get(descriptor, :headers),
         true <- Enum.all?(headers, &valid_header?/1),
         :ok <- validate_byte_cap(descriptor, byte_cap) do
      :ok
    else
      {:error, _reason} = error -> error
      _invalid -> {:error, :invalid_storage_descriptor}
    end
  end

  defp validate_descriptor(_descriptor, _method, _adapter, _byte_cap, _requested_expires_at),
    do: {:error, :invalid_storage_descriptor}

  defp valid_header?({name, value})
       when is_binary(name) and name != "" and is_binary(value),
       do: String.valid?(name) and String.valid?(value)

  defp valid_header?(_header), do: false

  defp validate_expiry(descriptor_expires_at, %DateTime{} = requested_expires_at) do
    cond do
      not DateTime.after?(descriptor_expires_at, DateTime.utc_now()) ->
        {:error, :storage_access_expired}

      DateTime.after?(descriptor_expires_at, requested_expires_at) ->
        {:error, :storage_access_expiry_exceeded}

      true ->
        :ok
    end
  end

  defp validate_expiry(_descriptor_expires_at, _requested_expires_at),
    do: {:error, :invalid_storage_descriptor}

  defp validate_byte_cap(_descriptor, nil), do: :ok

  defp validate_byte_cap(%{max_bytes: byte_cap}, byte_cap)
       when is_integer(byte_cap) and byte_cap > 0,
       do: :ok

  defp validate_byte_cap(_descriptor, _byte_cap), do: {:error, :byte_cap_not_enforced}

  defp validate_destination(%URI{scheme: "https", host: host}, adapter)
       when is_binary(host) do
    if host in adapter.approved_hosts() do
      :ok
    else
      {:error, :unapproved_storage_destination}
    end
  end

  defp validate_destination(%URI{scheme: scheme}, _adapter) when scheme != "https",
    do: {:error, :insecure_storage_destination}

  defp validate_destination(_uri, _adapter), do: {:error, :unapproved_storage_destination}
end
