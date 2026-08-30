defmodule QuickTrain.OidcProviderMetadataCacheTest do
  use ExUnit.Case, async: true

  alias QuickTrain.Accounts.OidcProviderMetadataCache

  test "reuses public provider metadata by issuer only until its cache deadline" do
    loader = start_supervised!({Agent, fn -> [{:ok, {:configuration, :jwks}, 60_000}] end})
    cache = start_cache(loader)

    assert {:ok, {:configuration, :jwks}} =
             OidcProviderMetadataCache.fetch(cache, "https://issuer.example.test")

    assert {:ok, {:configuration, :jwks}} =
             OidcProviderMetadataCache.fetch(cache, "https://issuer.example.test")

    assert Agent.get(loader, & &1) == []
  end

  test "expired metadata is not served when refresh fails" do
    loader =
      start_supervised!(
        {Agent, fn -> [{:ok, {:configuration, :jwks}, 0}, {:error, :provider_unavailable}] end}
      )

    cache = start_cache(loader)

    assert {:ok, {:configuration, :jwks}} =
             OidcProviderMetadataCache.fetch(cache, "https://issuer.example.test")

    assert {:error, :provider_unavailable} =
             OidcProviderMetadataCache.fetch(cache, "https://issuer.example.test")
  end

  def load(loader, "https://issuer.example.test") do
    Agent.get_and_update(loader, fn [result | remaining] -> {result, remaining} end)
  end

  defp start_cache(loader) do
    name = Module.concat(__MODULE__, "Cache#{System.unique_integer([:positive])}")

    start_supervised!(
      {OidcProviderMetadataCache, name: name, loader: {__MODULE__, :load, [loader]}}
    )

    name
  end
end
