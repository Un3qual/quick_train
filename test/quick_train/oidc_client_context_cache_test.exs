defmodule QuickTrain.OidcClientContextCacheTest do
  use ExUnit.Case, async: true

  alias QuickTrain.Accounts.OidcClientContextCache

  test "reuses a client context only until its provider cache deadline" do
    loader = start_supervised!({Agent, fn -> [{:ok, :client_context, 60_000}] end})
    cache = start_cache(loader)

    assert {:ok, :client_context} = OidcClientContextCache.fetch(cache, :configuration)
    assert {:ok, :client_context} = OidcClientContextCache.fetch(cache, :configuration)
    assert Agent.get(loader, & &1) == []
  end

  test "an expired context is not served when refresh fails" do
    loader =
      start_supervised!(
        {Agent, fn -> [{:ok, :client_context, 0}, {:error, :provider_unavailable}] end}
      )

    cache = start_cache(loader)

    assert {:ok, :client_context} = OidcClientContextCache.fetch(cache, :configuration)

    assert {:error, :provider_unavailable} =
             OidcClientContextCache.fetch(cache, :configuration)
  end

  def load(loader, _configuration) do
    Agent.get_and_update(loader, fn [result | remaining] -> {result, remaining} end)
  end

  defp start_cache(loader) do
    name = Module.concat(__MODULE__, "Cache#{System.unique_integer([:positive])}")

    start_supervised!({OidcClientContextCache, name: name, loader: {__MODULE__, :load, [loader]}})

    name
  end
end
