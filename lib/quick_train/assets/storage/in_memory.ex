defmodule QuickTrain.Assets.Storage.InMemory do
  @moduledoc "Deterministic in-memory storage for development and tests."

  use GenServer

  @behaviour QuickTrain.Assets.Storage

  alias QuickTrain.Assets.Storage.Content

  @host "storage.quicktrain.local"

  @impl true
  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  def reset, do: GenServer.call(__MODULE__, :reset)
  def set_publish_delay(delay_ms), do: GenServer.call(__MODULE__, {:set_publish_delay, delay_ms})

  def put_staging(descriptor, bytes),
    do: GenServer.call(__MODULE__, {:put_staging, token(descriptor), bytes})

  def read_sealed(descriptor), do: GenServer.call(__MODULE__, {:read_sealed, token(descriptor)})
  def sealed?(key), do: GenServer.call(__MODULE__, {:sealed?, key})
  def sealed_count, do: GenServer.call(__MODULE__, :sealed_count)

  @impl true
  def enforces_byte_cap?, do: true
  @impl true
  def approved_hosts, do: [@host]
  @impl true
  def writable_staging_access(key, cap, expires_at),
    do: GenServer.call(__MODULE__, {:issue_staging, key, cap, expires_at})

  @impl true
  def sealed_read_access(sealed, expires_at),
    do: GenServer.call(__MODULE__, {:issue_read, sealed, expires_at})

  @impl true
  def verify_and_publish(staging_key, sealed_key, expected, deadline_ms)
      when is_integer(deadline_ms) and deadline_ms > 0 do
    deadline = deadline_after(deadline_ms)

    with {:ok, bytes} <-
           call_before(deadline, &GenServer.call(__MODULE__, {:pin_staging, staging_key}, &1)),
         {:ok, facts} <- Content.verify(bytes, expected),
         {:ok, ^facts} <-
           call_before(
             deadline,
             &GenServer.call(__MODULE__, {:publish, sealed_key, bytes, facts}, &1)
           ),
         {:ok, ^facts} <-
           call_before(
             deadline,
             &GenServer.call(__MODULE__, {:verify_sealed, sealed_key, expected}, &1)
           ) do
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
    |> call_before(&GenServer.call(__MODULE__, {:verify_sealed, sealed_key, expected}, &1))
  end

  def verify_sealed(_sealed_key, _expected, _deadline_ms),
    do: {:error, :invalid_publication_deadline}

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

  @impl true
  def init(_opts), do: {:ok, fresh_state()}

  @impl true
  def handle_call(:reset, _from, _state), do: {:reply, :ok, fresh_state()}

  def handle_call({:set_publish_delay, delay_ms}, _from, state)
      when is_integer(delay_ms) and delay_ms >= 0 do
    {:reply, :ok, %{state | publish_delay_ms: delay_ms}}
  end

  def handle_call({:issue_staging, key, byte_cap, expires_at}, _from, state)
      when is_binary(key) and is_integer(byte_cap) and byte_cap > 0 do
    entry = Map.get(state.staging, key, %{bytes: nil, fenced: false})

    if entry.fenced do
      {:reply, {:error, :staging_fenced}, state}
    else
      {token, state} = next_token(state)

      descriptor = descriptor(:put, "upload", token, expires_at, byte_cap)

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
         %{fenced: false} = entry <- Map.get(state.staging, key),
         :ok <- unexpired(expires_at),
         :ok <- within_cap(bytes, byte_cap) do
      entry = %{entry | bytes: bytes}
      {:reply, :ok, %{state | staging: Map.put(state.staging, key, entry)}}
    else
      %{fenced: true} -> {:reply, {:error, :staging_fenced}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
      _missing -> {:reply, {:error, :invalid_storage_access}, state}
    end
  end

  def handle_call({:put_staging, _token, _bytes}, _from, state),
    do: {:reply, {:error, :invalid_storage_access}, state}

  def handle_call({:pin_staging, key}, _from, state) do
    case Map.get(state.staging, key) do
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
    case Map.get(state.sealed, key) do
      nil ->
        Process.sleep(state.publish_delay_ms)
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
        {:reply, Content.verify(bytes, expected), state}

      nil ->
        {:reply, {:error, :sealed_missing}, state}
    end
  end

  def handle_call({:issue_read, key, expires_at}, _from, state) do
    if Map.has_key?(state.sealed, key) do
      {token, state} = next_token(state)
      descriptor = descriptor(:get, "read", token, expires_at, nil)
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

  def handle_call(:sealed_count, _from, state), do: {:reply, map_size(state.sealed), state}

  defp fresh_state do
    %{
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

  defp descriptor(method, operation, token, expires_at, byte_cap) do
    %{
      method: method,
      uri: URI.parse("https://#{@host}/#{operation}/#{token}"),
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
end
