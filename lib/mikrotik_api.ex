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

  @base_path "/rest"

  @doc """
  Generic call. See get/3, post/4, put/4, patch/4, delete/3.
  opts: :body (map or list), :params (map), :headers (list), :scheme (:https | :http), :port (integer)
  """
  @spec call(Auth.t(), String.t(), method(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def call(%Auth{} = auth, ip, method, path, opts \\ []) when is_binary(ip) and is_binary(path) do
    started = System.monotonic_time()
    default_scheme = Application.get_env(:mikrotik_api, :default_scheme, :http)
    scheme = Keyword.get(opts, :scheme, default_scheme)
    port = Keyword.get(opts, :port, default_port(scheme))

    url = build_url(ip, port, scheme, path, Keyword.get(opts, :params, %{}))

    {headers, body} =
      build_request_parts(auth, method, Keyword.get(opts, :headers, []), Keyword.get(opts, :body))

    http_opts = httpc_options(auth)

    case transport_module().request(method, to_charlist(url), headers, body, http_opts: http_opts) do
      {:ok, {status, _resp_headers, resp_body}} ->
        duration_ms = monotonic_ms_since(started)
        Logger.debug(fn ->
          "mikrotik_api #{method} #{path} status=#{status} duration_ms=#{duration_ms}"
        end)

        handle_response(status, resp_body, opts)

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

  # -- resource helpers --

  @doc """
  GET /system/resource
  """
  @spec system_resource(Auth.t(), String.t(), Keyword.t()) :: {:ok, any() | nil} | {:error, Error.t()}
  def system_resource(auth, ip, opts \\ []) do
    get(auth, ip, "/system/resource", opts)
  end

  @doc """
  GET /interface
  """
  @spec interface_list(Auth.t(), String.t(), Keyword.t()) :: {:ok, any() | nil} | {:error, Error.t()}
  def interface_list(auth, ip, opts \\ []) do
    get(auth, ip, "/interface", opts)
  end

  @doc """
  GET /ip/address
  """
  @spec ip_address_list(Auth.t(), String.t(), Keyword.t()) :: {:ok, any() | nil} | {:error, Error.t()}
  def ip_address_list(auth, ip, opts \\ []) do
    get(auth, ip, "/ip/address", opts)
  end

  @doc """
  POST /ip/address
  """
  @spec ip_address_add(Auth.t(), String.t(), map() | list(), Keyword.t()) :: {:ok, any() | nil} | {:error, Error.t()}
  def ip_address_add(auth, ip, attrs, opts \\ []) when is_map(attrs) or is_list(attrs) do
    post(auth, ip, "/ip/address", attrs, opts)
  end

  @doc """
  PATCH /ip/address/{id}
  """
  @spec ip_address_update(Auth.t(), String.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def ip_address_update(auth, ip, id, attrs, opts \\ []) when is_binary(id) do
    patch(auth, ip, "/ip/address/#{id}", attrs, opts)
  end

  @doc """
  DELETE /ip/address/{id}
  """
  @spec ip_address_delete(Auth.t(), String.t(), String.t(), Keyword.t()) :: {:ok, any() | nil} | {:error, Error.t()}
  def ip_address_delete(auth, ip, id, opts \\ []) when is_binary(id) do
    delete(auth, ip, "/ip/address/#{id}", opts)
  end

  @doc """
  GET /ip/firewall/filter
  """
  @spec firewall_filter_list(Auth.t(), String.t(), Keyword.t()) :: {:ok, any() | nil} | {:error, Error.t()}
  def firewall_filter_list(auth, ip, opts \\ []) do
    get(auth, ip, "/ip/firewall/filter", opts)
  end

  @doc """
  POST /ip/firewall/filter
  """
  @spec firewall_filter_add(Auth.t(), String.t(), map() | list(), Keyword.t()) :: {:ok, any() | nil} | {:error, Error.t()}
  def firewall_filter_add(auth, ip, rule, opts \\ []) when is_map(rule) or is_list(rule) do
    post(auth, ip, "/ip/firewall/filter", rule, opts)
  end

  @doc """
  DELETE /ip/firewall/filter/{id}
  """
  @spec firewall_filter_delete(Auth.t(), String.t(), String.t(), Keyword.t()) :: {:ok, any() | nil} | {:error, Error.t()}
  def firewall_filter_delete(auth, ip, id, opts \\ []) when is_binary(id) do
    delete(auth, ip, "/ip/firewall/filter/#{id}", opts)
  end

  # -- internal helpers --

  defp transport_module do
    Application.get_env(:mikrotik_api, :transport, MikrotikApi.Transport.Httpc)
  end

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
    [{~c"content-type", ~c"application/json"} | headers]
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
      connect_timeout: auth.connect_timeout,
      timeout: auth.recv_timeout
    ]
  end

  defp handle_response(status, body, _opts) when status in 200..299 and (body == "" or status == 204) do
    {:ok, nil}
  end

  defp handle_response(status, body, opts) when status in 200..299 do
    if Keyword.get(opts, :decode, true) do
      case MikrotikApi.JSON.decode(body) do
        {:ok, data} -> {:ok, data}
        {:error, reason} -> {:error, %Error{status: status, reason: :decode_error, details: reason}}
      end
    else
      {:ok, body}
    end
  end

  defp handle_response(status, body, _opts) do
    {:error, %Error{status: status, reason: :http_error, details: truncate(body)}}
  end

  defp truncate(bin) when is_binary(bin) and byte_size(bin) > 4096, do: binary_part(bin, 0, 4096)
  defp truncate(bin), do: bin

  defp monotonic_ms_since(started) do
    System.convert_time_unit(System.monotonic_time() - started, :native, :millisecond)
  end
end
