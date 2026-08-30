defmodule QuickTrainWeb.Authentication.BearerAuthentication do
  @moduledoc false

  @behaviour Plug

  import Plug.Conn

  alias QuickTrain.Accounts

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case get_req_header(conn, "authorization") do
      [] ->
        conn

      [header] ->
        authenticate_header(conn, header)

      _invalid ->
        reject(conn)
    end
  end

  defp authenticate_header(conn, header) do
    case String.split(header, ~r/ +/, parts: 2, trim: true) do
      [scheme, token] when token != "" ->
        if String.downcase(scheme) == "bearer", do: authenticate(conn, token), else: reject(conn)

      _invalid ->
        reject(conn)
    end
  end

  defp authenticate(conn, token) do
    with {:ok, decoded} <- Base.url_decode64(token, padding: false),
         true <- byte_size(decoded) == 32,
         {:ok, %{user: user}} when not is_nil(user) <- lookup_session(token) do
      Ash.PlugHelpers.set_actor(conn, user)
    else
      _invalid -> reject(conn)
    end
  end

  defp lookup_session(token) do
    Accounts.authenticate_bearer_session(:crypto.hash(:sha256, token),
      authorize?: false,
      not_found_error?: false
    )
  end

  defp reject(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(401, Jason.encode!(%{error: "invalid_bearer_token"}))
    |> halt()
  end
end
