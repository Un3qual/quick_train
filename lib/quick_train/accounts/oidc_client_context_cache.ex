defmodule QuickTrain.Accounts.OidcClientContextCache do
  @moduledoc false

  use GenServer

  alias QuickTrain.Accounts.OidccProvider

  @call_timeout 30_000

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def fetch(configuration), do: fetch(__MODULE__, configuration)

  def fetch(server, configuration) do
    GenServer.call(server, {:fetch, configuration}, @call_timeout)
  end

  @impl true
  def init(opts) do
    loader = Keyword.get(opts, :loader, {OidccProvider, :load_client_context, []})
    {:ok, %{entry: nil, loader: loader}}
  end

  @impl true
  def handle_call({:fetch, configuration}, _from, state) do
    now = System.monotonic_time(:millisecond)

    case state.entry do
      %{configuration: ^configuration, expires_at: expires_at, context: context}
      when expires_at > now ->
        {:reply, {:ok, context}, state}

      _expired_or_changed ->
        refresh(configuration, now, state)
    end
  end

  defp refresh(configuration, now, state) do
    case run_loader(state.loader, configuration) do
      {:ok, context, lifetime_ms} when is_integer(lifetime_ms) and lifetime_ms >= 0 ->
        entry = %{
          configuration: configuration,
          context: context,
          expires_at: now + lifetime_ms
        }

        {:reply, {:ok, context}, %{state | entry: entry}}

      {:error, reason} ->
        {:reply, {:error, reason}, %{state | entry: nil}}
    end
  end

  defp run_loader({module, function, arguments}, configuration) do
    apply(module, function, arguments ++ [configuration])
  end
end
