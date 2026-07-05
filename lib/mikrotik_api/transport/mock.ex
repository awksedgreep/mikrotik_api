defmodule MikrotikApi.Transport.Mock do
  @moduledoc """
  In-memory transport for tests that need to mock MikroTik RouterOS REST endpoints.

  This module is part of the public testing API. It lets downstream projects test
  code that calls `MikrotikApi` without running a RouterOS device or opening a
  network connection.

  Configure it in your test setup:

      Application.put_env(:mikrotik_api, :transport, MikrotikApi.Transport.Mock)

  Then stub RouterOS paths for the current test process:

      MikrotikApi.Transport.Mock.stub(:get, "/system/resource", 200, %{"uptime" => "1h"})

  Stubs are isolated by process. For code that calls the API from another process,
  pass `owner_pid: self()` to the MikroTik API call so the worker process can use
  the test process' stubs.

  For lower-level assertions, use `put/1` with a five-arity function matching the
  `MikrotikApi.Transport` callback arguments.

  ## Stub Matching

  `stub/5` matches on the HTTP method and RouterOS path only. Host, port, scheme,
  query parameters, headers, and body are intentionally ignored. Use `put/1` when
  a test needs to assert on those request details.

  ## Response Bodies

  Map and list bodies are encoded with `JSON.encode!/1`; binary bodies are returned
  as-is; `nil` is returned as an empty response body.
  """

  @behaviour MikrotikApi.Transport

  @typedoc "HTTP method supported by the MikroTik REST client."
  @type method :: MikrotikApi.Transport.method()

  @typedoc "Mock response in the same shape returned by `MikrotikApi.Transport.request/5`."
  @type response ::
          {:ok, {pos_integer(), [{charlist(), charlist()}], binary()}}
          | {:error, term()}

  @typedoc """
  Low-level mock handler.

  The arguments are `method`, full URL, request headers, request body, and
  transport options.
  """
  @type handler ::
          (method(),
           MikrotikApi.Transport.url(),
           MikrotikApi.Transport.headers(),
           MikrotikApi.Transport.body(),
           keyword() ->
             response())

  @doc """
  Installs a low-level request handler for the current process.

  The handler receives `method`, `url`, `headers`, `body`, and transport `opts`.
  Use this when a test needs to assert on the exact URL, authorization header,
  request body, or HTTP options.

  The handler must return either `{:ok, {status, headers, body}}` or
  `{:error, reason}`.

  A low-level handler takes precedence over any stubs installed with `stub/5` for
  the same process.
  """
  @spec put(handler()) :: :ok
  def put(fun) when is_function(fun, 5) do
    :persistent_term.put(handler_key(self()), fun)
    :ok
  end

  @doc """
  Stubs a RouterOS REST path for the current process.

  `path` should be the RouterOS path without the `/rest` prefix, for example
  `"/system/resource"` or `"/ip/address"`.

  The stub is selected by `{method, path}`. For example:

      Mock.stub(:get, "/system/resource", 200, %{"uptime" => "1h"})
      Mock.stub(:put, "/ip/address", 201, nil)

  `body` can be:

  - a map or list, encoded as JSON
  - a binary, returned unchanged
  - `nil`, returned as an empty body

  `headers` are response headers and should use the same charlist tuple shape as
  the transport behaviour, for example `{~c"content-type", ~c"application/json"}`.
  """
  @spec stub(method(), String.t(), pos_integer(), binary() | map() | list() | nil, [
          {charlist(), charlist()}
        ]) :: :ok
  def stub(method, path, status, body \\ nil, headers \\ []) when is_integer(status) do
    route = {method, normalize_path(path)}
    response = {:ok, {status, headers, encode_body(body)}}

    routes =
      self()
      |> routes_key()
      |> :persistent_term.get(%{})
      |> Map.put(route, response)

    :persistent_term.put(routes_key(self()), routes)
    :ok
  end

  @doc """
  Clears mocks for the current process.

  Call this from test setup when using async tests to avoid stale stubs if a test
  process is reused.
  """
  @spec clear() :: :ok
  def clear do
    clear(self())
  end

  @doc """
  Clears mocks for a specific owner process.

  This is useful when a test installed stubs for a known owner process and cleanup
  happens from another process.
  """
  @spec clear(pid()) :: :ok
  def clear(owner) when is_pid(owner) do
    :persistent_term.erase(handler_key(owner))
    :persistent_term.erase(routes_key(owner))
    :ok
  end

  @impl true
  def request(method, url, headers, body, opts) do
    owner = Keyword.get(opts, :owner_pid, self())

    case :persistent_term.get(handler_key(owner), nil) do
      fun when is_function(fun, 5) ->
        fun.(method, url, headers, body, opts)

      nil ->
        request_stub(owner, method, url)
    end
  end

  defp request_stub(owner, method, url) do
    route = {method, request_path(url)}
    routes = :persistent_term.get(routes_key(owner), %{})

    case Map.fetch(routes, route) do
      {:ok, response} ->
        response

      :error ->
        raise "Mock not configured for #{inspect(method)} #{request_path(url)} owner_pid=#{inspect(owner)}"
    end
  end

  defp request_path(url) do
    url
    |> to_string()
    |> URI.parse()
    |> Map.fetch!(:path)
    |> normalize_path()
  end

  defp normalize_path("/rest/" <> path), do: "/" <> path
  defp normalize_path("/" <> _ = path), do: path
  defp normalize_path(path), do: "/" <> path

  defp encode_body(nil), do: ""
  defp encode_body(body) when is_binary(body), do: body
  defp encode_body(body) when is_map(body) or is_list(body), do: JSON.encode!(body)

  defp handler_key(owner), do: {__MODULE__, :handler, owner}
  defp routes_key(owner), do: {__MODULE__, :routes, owner}
end
