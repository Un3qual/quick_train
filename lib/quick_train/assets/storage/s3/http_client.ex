defmodule QuickTrain.Assets.Storage.S3.HTTPClient do
  @moduledoc false
  @behaviour ExAws.Request.HttpClient

  @control_limit 64 * 1024

  @impl true
  def request(method, url, body, headers, opts) do
    timeout = Keyword.get(opts, :timeout, 5_000)
    into = Keyword.get(opts, :into, &collect_control/2)

    result =
      Req.request(
        method: method,
        url: url,
        body: if(method in [:get, :head], do: nil, else: body),
        headers: headers,
        retry: false,
        redirect: false,
        decode_body: false,
        raw: true,
        compressed: false,
        finch: [
          pool_timeout: timeout,
          receive_timeout: timeout,
          conn_opts: [transport_opts: [timeout: 5_000] ++ Keyword.get(opts, :tls_options, [])]
        ],
        into: into
      )

    case result do
      {:ok, %{status: status}} when status in 300..399 ->
        {:error, %{reason: :storage_redirect}}

      {:ok, response} ->
        {:ok,
         %{
           status_code: response.status,
           headers: Req.get_headers_list(response),
           body: response.body,
           private: response.private
         }}

      {:error, _reason} ->
        {:error, %{reason: :storage_request_failed}}
    end
  catch
    {:storage_error, reason} -> {:error, %{reason: reason}}
  end

  def collect_control({:data, data}, {request, response}) do
    body = response.body <> data
    if byte_size(body) > @control_limit, do: throw({:storage_error, :storage_response_too_large})
    {:cont, {request, %{response | body: body}}}
  end
end
