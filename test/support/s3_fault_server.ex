defmodule QuickTrainWeb.S3FaultServer do
  @moduledoc false
  import Plug.Conn

  def init(handler), do: handler
  def call(conn, handler), do: handler.(conn)

  def start(handler) do
    directory = System.fetch_env!("QUICK_TRAIN_STORAGE_CA_FILE") |> Path.dirname()

    pid =
      ExUnit.Callbacks.start_supervised!(
        {Bandit,
         plug: {__MODULE__, handler},
         scheme: :https,
         ip: {127, 0, 0, 1},
         port: 0,
         certfile: Path.join(directory, "server.pem"),
         keyfile: Path.join(directory, "server.key"),
         startup_log: false}
      )

    {:ok, {_address, port}} = ThousandIsland.listener_info(pid)
    "https://127.0.0.1:#{port}"
  end

  def forward(conn, upstream) do
    limit = Application.fetch_env!(:quick_train, :assets) |> Keyword.fetch!(:max_bytes)
    {:ok, body, conn} = read_body(conn, length: limit)

    url =
      upstream <>
        conn.request_path <> if(conn.query_string == "", do: "", else: "?" <> conn.query_string)

    response =
      Req.request!(
        method: String.downcase(conn.method) |> String.to_existing_atom(),
        url: url,
        body: if(conn.method in ["GET", "HEAD"], do: nil, else: body),
        headers:
          Enum.reject(conn.req_headers, fn {name, _} ->
            name in ["connection", "transfer-encoding"]
          end),
        retry: false,
        redirect: false,
        decode_body: false,
        raw: true,
        connect_options: [
          transport_opts: [cacertfile: System.fetch_env!("QUICK_TRAIN_STORAGE_CA_FILE")]
        ]
      )

    {conn, response}
  end

  def respond({conn, response}) do
    headers =
      Req.get_headers_list(response)
      |> Enum.reject(fn {name, _} ->
        name in ["connection", "transfer-encoding", "date", "server"]
      end)

    conn |> merge_resp_headers(headers) |> send_resp(response.status, response.body)
  end
end
