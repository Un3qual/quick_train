defmodule QuickTrain.Assets.Storage.S3.HTTPClient do
  @moduledoc false
  @behaviour ExAws.Request.HttpClient

  @control_limit 64 * 1024

  @impl true
  def request(method, url, body, headers, opts) do
    body = if method in [:get, :head], do: nil, else: body

    with {:ok, response} <-
           request([method: method, url: url, body: body, headers: headers] ++ opts) do
      {:ok,
       %{
         status_code: response.status,
         headers: Req.get_headers_list(response),
         body: response.body
       }}
    end
  end

  def request(options) do
    {timeout, options} = Keyword.pop(options, :timeout, 5_000)
    {tls_options, options} = Keyword.pop(options, :tls_options, [])
    options = Keyword.put_new(options, :into, &collect_control/2)

    result =
      Req.request(
        options,
        retry: &retry_conflict/2,
        max_retries: 1,
        retry_log_level: false,
        redirect: false,
        decode_body: false,
        raw: true,
        compressed: false,
        finch: [
          pool_timeout: timeout,
          receive_timeout: timeout,
          conn_opts: [transport_opts: [timeout: 5_000] ++ tls_options]
        ]
      )

    case result do
      {:ok, %{status: status}} when status in 300..399 ->
        {:error, %{reason: :storage_redirect}}

      {:ok, response} ->
        {:ok, response}

      {:error, _reason} ->
        {:error, %{reason: :storage_request_failed}}
    end
  catch
    {:storage_error, reason} -> {:error, %{reason: reason}}
  end

  defp retry_conflict(%{method: :put} = request, %{status: 409}) do
    if Req.Request.get_header(request, "if-none-match") == ["*"], do: {:delay, 0}, else: false
  end

  defp retry_conflict(_request, _response), do: false

  def collect_control({:data, data}, {request, response}) do
    body = response.body <> data
    if byte_size(body) > @control_limit, do: throw({:storage_error, :storage_response_too_large})
    {:cont, {request, %{response | body: body}}}
  end
end
