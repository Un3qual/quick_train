defmodule QuickTrainWeb.Authentication.RequestSecurity do
  @moduledoc false

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    settings = Application.fetch_env!(:quick_train, :authentication)
    network_source = network_source(conn, settings)

    conn =
      conn
      |> assign(:authentication_network_source, network_source)
      |> Ash.PlugHelpers.set_context(%{authentication_network_source: network_source})
      |> maybe_prevent_graphql_caching()

    if encrypted_transport_required?(conn, settings) and not encrypted?(conn, settings) do
      conn
      |> put_resp_content_type("application/json")
      |> put_resp_header("cache-control", "no-store")
      |> send_resp(426, Jason.encode!(%{error: "encrypted_transport_required"}))
      |> halt()
    else
      conn
    end
  end

  defp maybe_prevent_graphql_caching(conn) do
    if graphql_path?(conn.request_path),
      do: put_resp_header(conn, "cache-control", "no-store"),
      else: conn
  end

  defp encrypted_transport_required?(conn, settings) do
    enforce_https? = Keyword.fetch!(settings, :enforce_https?)
    bearer_present? = get_req_header(conn, "authorization") != []

    enforce_https? and (graphql_path?(conn.request_path) or bearer_present?)
  end

  defp encrypted?(conn, settings) do
    if trusted_proxy?(conn.remote_ip, settings) do
      case forwarded_value(conn, "x-forwarded-proto") do
        nil -> false
        value -> String.downcase(value) in ["https", "wss"]
      end
    else
      conn.scheme == :https
    end
  end

  defp network_source(conn, settings) do
    if trusted_proxy?(conn.remote_ip, settings) do
      conn
      |> get_req_header("x-forwarded-for")
      |> List.first()
      |> forwarded_addresses()
      |> Enum.reverse()
      |> Enum.drop_while(&trusted_proxy?(&1, settings))
      |> List.first()
      |> Kernel.||(conn.remote_ip)
      |> :inet.ntoa()
      |> to_string()
    else
      conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end

  defp trusted_proxy?(address, settings) when is_tuple(address) do
    settings
    |> Keyword.fetch!(:trusted_proxy_ips)
    |> Enum.any?(fn configured -> parse_ip(configured) == {:ok, address} end)
  end

  defp trusted_proxy?(_address, _settings), do: false

  defp forwarded_addresses(nil), do: []

  defp forwarded_addresses(header) do
    header
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.flat_map(fn value ->
      case parse_ip(value) do
        {:ok, address} -> [address]
        :error -> []
      end
    end)
  end

  defp forwarded_value(conn, header) do
    conn
    |> get_req_header(header)
    |> Enum.flat_map(&String.split(&1, ",", trim: false))
    |> List.last()
    |> trimmed_value()
  end

  defp trimmed_value(nil), do: nil

  defp trimmed_value(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp graphql_path?("/graphql"), do: true
  defp graphql_path?("/graphql/" <> _subpath), do: true
  defp graphql_path?(_path), do: false

  defp parse_ip(address) when is_tuple(address), do: {:ok, address}

  defp parse_ip(address) when is_binary(address),
    do: :inet.parse_address(String.to_charlist(address))

  defp parse_ip(_address), do: :error
end
