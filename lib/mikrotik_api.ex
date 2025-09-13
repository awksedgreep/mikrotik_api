defmodule MikrotikApi do
  @moduledoc """
  Public API for interacting with MikroTik RouterOS REST endpoints.

  Usage pattern:
  - Establish an %MikrotikApi.Auth{} once.
  - Pass Auth and a target IP (IPv4/IPv6 literal) to each call.

  Transport and JSON are internal. Logging uses Logger only.
  """

  require Logger
  alias MikrotikApi.{Auth, Error}

  @type method :: :get | :post | :put | :patch | :delete

  @transport Application.compile_env(:mikrotik_api, :transport, MikrotikApi.Transport.Httpc)
  @base_path "/rest"

  @doc """
  Generic call. See get/3, post/4, put/4, patch/4, delete/3.
  opts: :body (map or list), :params (map), :headers (list), :scheme (:https | :http), :port (integer)
  """
  @spec call(Auth.t(), String.t(), method(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def call(%Auth{} = auth, ip, method, path, opts \\ []) when is_binary(ip) and is_binary(path) do
    started = System.monotonic_time()
    scheme = Keyword.get(opts, :scheme, :https)
    port = Keyword.get(opts, :port, default_port(scheme))

    url = build_url(ip, port, scheme, path, Keyword.get(opts, :params, %{}))

    {headers, body} =
      build_request_parts(auth, method, Keyword.get(opts, :headers, []), Keyword.get(opts, :body))

    http_opts = httpc_options(auth)

    case @transport.request(method, to_charlist(url), headers, body, http_opts: http_opts) do
      {:ok, {status, _resp_headers, resp_body}} ->
        duration_ms = monotonic_ms_since(started)
        Logger.debug(fn ->
          "mikrotik_api #{method} #{path} status=#{status} duration_ms=#{duration_ms}"
        end)

        handle_response(status, resp_body)

      {:error, reason} ->
        duration_ms = monotonic_ms_since(started)
        Logger.error("mikrotik_api #{method} #{path} transport_error duration_ms=#{duration_ms}")
        {:error, %Error{status: nil, reason: :transport_error, details: reason}}
    end
  end

  @doc """
  GET a path under /rest on the target.
  """
  @spec get(Auth.t(), String.t(), String.t(), Keyword.t()) :: {:ok, any() | nil} | {:error, Error.t()}
  def get(auth, ip, path, opts \\ []) do
    call(auth, ip, :get, path, opts)
  end

  @doc """
  POST JSON to a path under /rest on the target.
  """
  @spec post(Auth.t(), String.t(), String.t(), map() | list() | nil, Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def post(auth, ip, path, body \\ nil, opts \\ []) do
    call(auth, ip, :post, path, Keyword.put(opts, :body, body))
  end

  @doc """
  PUT JSON to a path under /rest on the target.
  """
  @spec put(Auth.t(), String.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def put(auth, ip, path, body, opts \\ []) do
    call(auth, ip, :put, path, Keyword.put(opts, :body, body))
  end

  @doc """
  PATCH JSON to a path under /rest on the target.
  """
  @spec patch(Auth.t(), String.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def patch(auth, ip, path, body, opts \\ []) do
    call(auth, ip, :patch, path, Keyword.put(opts, :body, body))
  end

  @doc """
  DELETE a path under /rest on the target.
  """
  @spec delete(Auth.t(), String.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def delete(auth, ip, path, opts \\ []) do
    call(auth, ip, :delete, path, opts)
  end

  # -- internal helpers --

  defp default_port(:https), do: 443
  defp default_port(:http), do: 80

  defp build_url(ip, port, scheme, path, params) do
    host = if String.contains?(ip, ":"), do: "[#{ip}]", else: ip
    base = "#{scheme}://#{host}:#{port}#{@base_path}"
    qs = encode_query(params)
    base <> path <> qs
  end

  defp encode_query(%{} = params) when map_size(params) == 0, do: ""
  defp encode_query(%{} = params) do
    encoded =
      params
      |> Enum.flat_map(fn {k, v} ->
        case v do
          nil -> []
          _ -> [URI.encode_www_form(to_string(k)) <> "=" <> URI.encode_www_form(to_string(v))]
        end
      end)
      |> Enum.join("&")

    if encoded == "", do: "", else: "?" <> encoded
  end

  defp build_request_parts(%Auth{} = auth, method, extra_headers, body_term) do
    auth_header = basic_auth_header(auth)

    headers =
      auth.default_headers
      |> Kernel.++(extra_headers)
      |> Kernel.++([{"authorization", auth_header}])
      |> Enum.map(fn {k, v} -> {to_charlist(k), to_charlist(v)} end)

    case method do
      m when m in [:post, :put, :patch] ->
        json =
          case body_term do
            nil -> "null"
            _ -> MikrotikApi.JSON.encode!(body_term)
          end

        {headers_with_ct(headers), to_charlist(json)}

      _ ->
        {headers, :undefined}
    end
  end

  defp headers_with_ct(headers) do
    [{'content-type', 'application/json'} | headers]
  end

  defp basic_auth_header(%Auth{username: u, password: p}) do
    "Basic " <> Base.encode64("#{u}:#{p}")
  end

  defp httpc_options(%Auth{} = auth) do
    ssl_verify =
      case auth.verify do
        :verify_none -> [verify: :verify_none]
        _ -> [verify: :verify_peer]
      end

    [
      ssl: ssl_verify,
      timeout: auth.connect_timeout,
      recv_timeout: auth.recv_timeout
    ]
  end

  defp handle_response(status, body) when status in 200..299 do
    cond do
      body == "" or status == 204 -> {:ok, nil}
      true ->
        case MikrotikApi.JSON.decode(body) do
          {:ok, data} -> {:ok, data}
          {:error, reason} -> {:error, %Error{status: status, reason: :decode_error, details: reason}}
        end
    end
  end

  defp handle_response(status, body) do
    {:error, %Error{status: status, reason: :http_error, details: truncate(body)}}
  end

  defp truncate(bin) when is_binary(bin) and byte_size(bin) > 4096, do: binary_part(bin, 0, 4096)
  defp truncate(bin), do: bin

  defp monotonic_ms_since(started) do
    System.convert_time_unit(System.monotonic_time() - started, :native, :millisecond)
  end
end

defmodule MikrotikApi do
  @moduledoc """
  Documentation for `MikrotikApi`.
  """

  @doc """
  Hello world.

  ## Examples

      iex> MikrotikApi.hello()
      :world

  """
  def hello do
    :world
  end
end
