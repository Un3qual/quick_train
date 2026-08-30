defmodule QuickTrain.Accounts.OidcProviderMetadataCache do
  @moduledoc false

  use GenServer

  alias QuickTrain.Accounts.OidccProvider

  @call_timeout 30_000

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def fetch(issuer), do: fetch(__MODULE__, issuer)

  def fetch(server, issuer) do
    GenServer.call(server, {:fetch, issuer}, @call_timeout)
  end

  @impl true
  def init(opts) do
    loader = Keyword.get(opts, :loader, {OidccProvider, :load_provider_metadata, []})
    {:ok, %{entry: nil, loader: loader}}
  end

  @impl true
  def handle_call({:fetch, issuer}, _from, state) do
    now = System.monotonic_time(:millisecond)

    case state.entry do
      %{issuer: ^issuer, expires_at: expires_at, metadata: metadata}
      when expires_at > now ->
        {:reply, {:ok, metadata}, state}

      _expired_or_changed ->
        refresh(issuer, now, state)
    end
  end

  defp refresh(issuer, now, state) do
    case run_loader(state.loader, issuer) do
      {:ok, metadata, lifetime_ms} when is_integer(lifetime_ms) and lifetime_ms >= 0 ->
        entry = %{
          issuer: issuer,
          metadata: metadata,
          expires_at: now + lifetime_ms
        }

        {:reply, {:ok, metadata}, %{state | entry: entry}}

      {:error, reason} ->
        {:reply, {:error, reason}, %{state | entry: nil}}
    end
  end

  defp run_loader({module, function, arguments}, issuer) do
    apply(module, function, arguments ++ [issuer])
  end
end
