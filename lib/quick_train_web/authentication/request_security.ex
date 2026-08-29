defmodule QuickTrainWeb.Authentication.RequestSecurity do
  @moduledoc false

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    settings = Application.get_env(:quick_train, :authentication, [])
    network_source = network_source(conn, settings)

    conn =
      conn
      |> assign(:authentication_network_source, network_source)
      |> Absinthe.Plug.assign_context(authentication_network_source: network_source)
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

  defp maybe_prevent_graphql_caching(%Plug.Conn{request_path: "/graphql"} = conn),
    do: put_resp_header(conn, "cache-control", "no-store")

  defp maybe_prevent_graphql_caching(conn), do: conn

  defp encrypted_transport_required?(conn, settings) do
    enforce_https? = Keyword.get(settings, :enforce_https?, false)
    bearer_present? = get_req_header(conn, "authorization") != []

    enforce_https? and (conn.request_path == "/graphql" or bearer_present?)
  end

  defp encrypted?(conn, settings) do
    if trusted_proxy?(conn.remote_ip, settings) do
      case forwarded_value(conn, "x-forwarded-proto") do
        nil -> conn.scheme == :https
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
    |> Keyword.get(:trusted_proxy_ips, [])
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
    |> List.first()
    |> case do
      nil -> nil
      value -> value |> String.split(",", trim: true) |> List.last() |> String.trim()
    end
  end

  defp parse_ip(address) when is_tuple(address), do: {:ok, address}

  defp parse_ip(address) when is_binary(address),
    do: :inet.parse_address(String.to_charlist(address))

  defp parse_ip(_address), do: :error
end
