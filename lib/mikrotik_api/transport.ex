defmodule MikrotikApi.Transport do
  @moduledoc """
  Behaviour for pluggable MikroTik API transports.

  The default transport is `MikrotikApi.Transport.Httpc`. Tests can use
  `MikrotikApi.Transport.Mock` to stub RouterOS REST endpoints without a device.

  Custom transports must implement `request/5` and return the same shape as
  Erlang `:httpc` responses after normalization:

      {:ok, {status, response_headers, response_body}}
      {:error, reason}
  """
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
