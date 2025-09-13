defmodule MikrotikApi.Transport do
  @moduledoc false
  @type method :: :get | :post | :put | :patch | :delete
  @type headers :: [{charlist(), charlist()}]
  @type url :: charlist()
  @type body :: iodata() | :undefined
  @type status :: pos_integer()
  @type resp_headers :: [{charlist(), charlist()}]
  @type resp_body :: binary()

  @callback request(method, url, headers, body, keyword()) ::
              {:ok, {status, resp_headers, resp_body}} | {:error, term()}
end
