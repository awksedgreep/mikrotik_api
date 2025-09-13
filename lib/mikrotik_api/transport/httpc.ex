defmodule MikrotikApi.Transport.Httpc do
  @behaviour MikrotikApi.Transport
  require Logger

  @impl true
  def request(method, url, headers, body, opts) do
    {meth, request} =
      case method do
        :get -> {:get, {url, headers}}
        :delete -> {:delete, {url, headers}}
        m when m in [:post, :put, :patch] -> {m, {url, headers, ~c"application/json", body}}
      end

    http_opts = Keyword.get(opts, :http_opts, [])
    resp = :httpc.request(meth, request, http_opts, [body_format: :binary])

    case resp do
      {:ok, {{_http, status, _reason}, resp_headers, resp_body}} ->
        {:ok, {status, resp_headers, resp_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
