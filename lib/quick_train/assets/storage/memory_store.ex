defmodule QuickTrain.Assets.Storage.MemoryStore do
  @moduledoc false

  use GenServer

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    host = Keyword.fetch!(opts, :host)
    GenServer.start_link(__MODULE__, host, name: name)
  end

  def reset(server), do: GenServer.call(server, :reset)

  def set_publish_delay(server, delay_ms),
    do: GenServer.call(server, {:set_publish_delay, delay_ms})

  def issue_staging(server, key, byte_cap, expires_at),
    do: GenServer.call(server, {:issue_staging, key, byte_cap, expires_at})

  def put_staging(server, descriptor, bytes),
    do: GenServer.call(server, {:put_staging, token(descriptor), bytes})

  def pin_staging(server, key), do: GenServer.call(server, {:pin_staging, key})

  def publish(server, key, bytes, facts),
    do: GenServer.call(server, {:publish, key, bytes, facts})

  def verify_sealed(server, key, expected),
    do: GenServer.call(server, {:verify_sealed, key, expected})

  def retire_staging(server, key, not_before),
    do: GenServer.call(server, {:retire_staging, key, not_before})

  def issue_read(server, key, expires_at),
    do: GenServer.call(server, {:issue_read, key, expires_at})

  def read_sealed(server, descriptor),
    do: GenServer.call(server, {:read_sealed, token(descriptor)})

  def sealed?(server, key), do: GenServer.call(server, {:sealed?, key})
  def staging?(server, key), do: GenServer.call(server, {:staging?, key})
  def sealed_count(server), do: GenServer.call(server, :sealed_count)

  @impl true
  def init(host), do: {:ok, fresh_state(host)}

  @impl true
  def handle_call(:reset, _from, state), do: {:reply, :ok, fresh_state(state.host)}

  def handle_call({:set_publish_delay, delay_ms}, _from, state)
      when is_integer(delay_ms) and delay_ms >= 0 do
    {:reply, :ok, %{state | publish_delay_ms: delay_ms}}
  end

  def handle_call({:issue_staging, key, byte_cap, expires_at}, _from, state)
      when is_binary(key) and is_integer(byte_cap) and byte_cap > 0 do
    entry = Map.get(state.staging, key, %{bytes: nil, fenced: false, retired: false})

    cond do
      entry.retired ->
        {:reply, {:error, :staging_retired}, state}

      entry.fenced ->
        {:reply, {:error, :staging_fenced}, state}

      true ->
        {token, state} = next_token(state)

        descriptor = descriptor(state.host, :put, "upload", token, expires_at, byte_cap)

        state = %{
          state
          | staging: Map.put(state.staging, key, entry),
            upload_tokens:
              Map.put(state.upload_tokens, token, %{
                key: key,
                byte_cap: byte_cap,
                expires_at: expires_at
              })
        }

        {:reply, {:ok, descriptor}, state}
    end
  end

  def handle_call({:issue_staging, _key, _byte_cap, _expires_at}, _from, state),
    do: {:reply, {:error, :invalid_staging_access}, state}

  def handle_call({:put_staging, token, bytes}, _from, state) when is_binary(bytes) do
    with %{key: key, byte_cap: byte_cap, expires_at: expires_at} <-
           Map.get(state.upload_tokens, token),
         %{retired: false, fenced: false} = entry <- Map.get(state.staging, key),
         :ok <- unexpired(expires_at),
         :ok <- within_cap(bytes, byte_cap) do
      entry = %{entry | bytes: bytes}
      {:reply, :ok, %{state | staging: Map.put(state.staging, key, entry)}}
    else
      %{retired: true} -> {:reply, {:error, :staging_retired}, state}
      %{fenced: true} -> {:reply, {:error, :staging_fenced}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
      _missing -> {:reply, {:error, :invalid_storage_access}, state}
    end
  end

  def handle_call({:put_staging, _token, _bytes}, _from, state),
    do: {:reply, {:error, :invalid_storage_access}, state}

  def handle_call({:pin_staging, key}, _from, state) do
    case Map.get(state.staging, key) do
      %{retired: true} ->
        {:reply, {:error, :staging_retired}, state}

      %{bytes: nil} ->
        {:reply, {:error, :staging_missing}, state}

      %{bytes: bytes} = entry ->
        state = %{state | staging: Map.put(state.staging, key, %{entry | fenced: true})}
        {:reply, {:ok, bytes}, state}

      nil ->
        {:reply, {:error, :staging_missing}, state}
    end
  end

  def handle_call({:publish, key, bytes, facts}, _from, state) do
    Process.sleep(state.publish_delay_ms)

    case Map.get(state.sealed, key) do
      nil ->
        sealed = Map.put(state.sealed, key, %{bytes: bytes, facts: facts})
        {:reply, {:ok, facts}, %{state | sealed: sealed}}

      %{bytes: ^bytes, facts: ^facts} ->
        {:reply, {:ok, facts}, state}

      _conflict ->
        {:reply, {:error, :canonical_conflict}, state}
    end
  end

  def handle_call({:verify_sealed, key, expected}, _from, state) do
    case Map.get(state.sealed, key) do
      %{bytes: bytes} ->
        {:reply, QuickTrain.Assets.Storage.Content.verify(bytes, expected), state}

      nil ->
        {:reply, {:error, :sealed_missing}, state}
    end
  end

  def handle_call({:retire_staging, key, not_before}, _from, state) do
    now = DateTime.utc_now()

    case Map.get(state.staging, key) do
      nil ->
        {:reply, :ok, state}

      %{retired: true} ->
        {:reply, :ok, state}

      entry ->
        tokens = Enum.filter(state.upload_tokens, fn {_token, token} -> token.key == key end)
        latest_expiry = tokens |> Enum.map(fn {_token, value} -> value.expires_at end) |> latest()

        if DateTime.compare(now, not_before) != :lt and expired?(latest_expiry, now) do
          retired = %{entry | retired: true, fenced: true, bytes: nil}
          {:reply, :ok, %{state | staging: Map.put(state.staging, key, retired)}}
        else
          {:reply, {:error, :staging_access_still_active}, state}
        end
    end
  end

  def handle_call({:issue_read, key, expires_at}, _from, state) do
    if Map.has_key?(state.sealed, key) do
      {token, state} = next_token(state)
      descriptor = descriptor(state.host, :get, "read", token, expires_at, nil)
      read_tokens = Map.put(state.read_tokens, token, %{key: key, expires_at: expires_at})
      {:reply, {:ok, descriptor}, %{state | read_tokens: read_tokens}}
    else
      {:reply, {:error, :sealed_missing}, state}
    end
  end

  def handle_call({:read_sealed, token}, _from, state) do
    with %{key: key, expires_at: expires_at} <- Map.get(state.read_tokens, token),
         :ok <- unexpired(expires_at),
         %{bytes: bytes} <- Map.get(state.sealed, key) do
      {:reply, {:ok, bytes}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
      _missing -> {:reply, {:error, :invalid_storage_access}, state}
    end
  end

  def handle_call({:sealed?, key}, _from, state),
    do: {:reply, Map.has_key?(state.sealed, key), state}

  def handle_call({:staging?, key}, _from, state) do
    present? =
      match?(%{retired: false, bytes: bytes} when not is_nil(bytes), Map.get(state.staging, key))

    {:reply, present?, state}
  end

  def handle_call(:sealed_count, _from, state), do: {:reply, map_size(state.sealed), state}

  defp fresh_state(host) do
    %{
      host: host,
      counter: 0,
      publish_delay_ms: 0,
      staging: %{},
      sealed: %{},
      upload_tokens: %{},
      read_tokens: %{}
    }
  end

  defp next_token(state) do
    counter = state.counter + 1
    {Integer.to_string(counter, 36), %{state | counter: counter}}
  end

  defp descriptor(host, method, operation, token, expires_at, byte_cap) do
    %{
      method: method,
      uri: URI.parse("https://#{host}/#{operation}/#{token}"),
      headers: [{"cache-control", "no-store"}],
      expires_at: expires_at,
      cache_control: "no-store",
      referrer_policy: "no-referrer"
    }
    |> maybe_put_max_bytes(byte_cap)
  end

  defp maybe_put_max_bytes(descriptor, nil), do: descriptor
  defp maybe_put_max_bytes(descriptor, byte_cap), do: Map.put(descriptor, :max_bytes, byte_cap)

  defp token(%{uri: %URI{path: path}}) when is_binary(path) do
    path |> String.split("/", trim: true) |> List.last()
  end

  defp token(%{uri: uri}) when is_binary(uri), do: token(%{uri: URI.parse(uri)})

  defp token(_descriptor), do: nil

  defp within_cap(bytes, byte_cap) when byte_size(bytes) <= byte_cap, do: :ok
  defp within_cap(_bytes, _byte_cap), do: {:error, :byte_cap_exceeded}

  defp unexpired(%DateTime{} = expires_at) do
    if DateTime.compare(DateTime.utc_now(), expires_at) == :gt,
      do: {:error, :storage_access_expired},
      else: :ok
  end

  defp unexpired(_expires_at), do: {:error, :invalid_storage_access}

  defp latest([]), do: nil
  defp latest(expiries), do: Enum.max(expiries, DateTime)

  defp expired?(nil, _now), do: true
  defp expired?(expires_at, now), do: DateTime.compare(expires_at, now) != :gt
end
