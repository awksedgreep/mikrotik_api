defmodule MikrotikApi do
  @moduledoc """
  Public API for interacting with MikroTik RouterOS REST endpoints.

  Usage pattern:
  - Establish an %MikrotikApi.Auth{} once.
  - Pass Auth and a target IP (IPv4/IPv6 literal) to each call.

  Transport via OTP; JSON via Elixir's built-in JSON. Logging uses Logger only.
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

    case transport_module().request(method, to_charlist(url), headers, body,
           http_opts: http_opts,
           owner_pid: Keyword.get(opts, :owner_pid, self())
         ) do
      {:ok, {status, _resp_headers, resp_body}} ->
        duration_ms = monotonic_ms_since(started)

        Logger.debug(fn ->
          "mikrotik_api #{method} #{path} status=#{status} duration_ms=#{duration_ms}"
        end)

        opts_with_path = Keyword.put(opts, :_path, path)
        handle_response(status, resp_body, opts_with_path)

      {:error, reason} ->
        duration_ms = monotonic_ms_since(started)
        Logger.error("mikrotik_api #{method} #{path} transport_error duration_ms=#{duration_ms}")
        {:error, %Error{status: nil, reason: :transport_error, details: reason}}
    end
  end

  @doc """
  GET a path under /rest on the target.
  """
  @spec get(Auth.t(), String.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
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
  @spec system_resource(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def system_resource(auth, ip, opts \\ []) do
    get(auth, ip, "/system/resource", opts)
  end

  @doc """
  GET /interface
  """
  @spec interface_list(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def interface_list(auth, ip, opts \\ []) do
    get(auth, ip, "/interface", opts)
  end

  @doc """
  GET /ip/address
  """
  @spec ip_address_list(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def ip_address_list(auth, ip, opts \\ []) do
    get(auth, ip, "/ip/address", opts)
  end

  @doc """
  POST /ip/address
  """
  @spec ip_address_add(Auth.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def ip_address_add(auth, ip, attrs, opts \\ []) when is_map(attrs) or is_list(attrs) do
    post(auth, ip, "/ip/address", attrs, opts)
  end

  @doc """
  Ensure an IP address exists on an interface.
  Requires attrs to include at least "address" and optionally "interface"; matches existing entries by these keys.
  Returns {:ok, address} when found or created.
  """
  @spec ip_address_ensure(Auth.t(), String.t(), map(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def ip_address_ensure(auth, ip, attrs, opts \\ []) when is_map(attrs) do
    with {:ok, list} <- ip_address_list(auth, ip, opts) do
      addr = Map.get(attrs, "address")

      if is_nil(addr) do
        {:error, %Error{status: nil, reason: :invalid_argument, details: "address required"}}
      else
        iface = Map.get(attrs, "interface")

        exists? =
          Enum.any?(list, fn e ->
            match_addr = e["address"] == addr
            match_iface = is_nil(iface) or e["interface"] == iface
            match_addr and match_iface
          end)

        if exists? do
          {:ok, addr}
        else
          case ip_address_add(auth, ip, attrs, opts) do
            {:ok, _} -> {:ok, addr}
            {:error, _} = err -> err
          end
        end
      end
    end
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
  @spec ip_address_delete(Auth.t(), String.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def ip_address_delete(auth, ip, id, opts \\ []) when is_binary(id) do
    delete(auth, ip, "/ip/address/#{id}", opts)
  end

  @doc """
  GET /ip/firewall/filter
  """
  @spec firewall_filter_list(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def firewall_filter_list(auth, ip, opts \\ []) do
    get(auth, ip, "/ip/firewall/filter", opts)
  end

  @doc """
  POST /ip/firewall/filter
  """
  @spec firewall_filter_add(Auth.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def firewall_filter_add(auth, ip, rule, opts \\ []) when is_map(rule) or is_list(rule) do
    post(auth, ip, "/ip/firewall/filter", rule, opts)
  end

  @doc """
  Ensure a firewall filter rule exists.
  By default, matches existing by ["chain", "action"]. You can pass unique_keys: [..] in opts to control matching.
  Returns {:ok, Map.t()} with the matched key-values when found or created.
  """
  @spec firewall_filter_ensure(Auth.t(), String.t(), map(), Keyword.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def firewall_filter_ensure(auth, ip, rule, opts \\ []) when is_map(rule) do
    unique_keys = Keyword.get(opts, :unique_keys, ["chain", "action"])

    with {:ok, list} <- firewall_filter_list(auth, ip, opts) do
      found =
        Enum.find(list, fn e ->
          Enum.all?(unique_keys, fn k -> Map.get(e, k) == Map.get(rule, k) end)
        end)

      if found do
        {:ok, Map.new(unique_keys, fn k -> {k, Map.get(found, k)} end)}
      else
        case firewall_filter_add(auth, ip, rule, opts) do
          {:ok, _} -> {:ok, Map.new(unique_keys, fn k -> {k, Map.get(rule, k)} end)}
          {:error, _} = err -> err
        end
      end
    end
  end

  @doc """
  DELETE /ip/firewall/filter/{id}
  """
  @spec firewall_filter_delete(Auth.t(), String.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def firewall_filter_delete(auth, ip, id, opts \\ []) when is_binary(id) do
    delete(auth, ip, "/ip/firewall/filter/#{id}", opts)
  end

  # Firewall NAT

  @doc """
  GET /ip/firewall/nat
  """
  @spec firewall_nat_list(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def firewall_nat_list(auth, ip, opts \\ []) do
    get(auth, ip, "/ip/firewall/nat", opts)
  end

  @doc """
  POST /ip/firewall/nat
  """
  @spec firewall_nat_add(Auth.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def firewall_nat_add(auth, ip, rule, opts \\ []) when is_map(rule) or is_list(rule) do
    post(auth, ip, "/ip/firewall/nat", rule, opts)
  end

  @doc """
  DELETE /ip/firewall/nat/{id}
  """
  @spec firewall_nat_delete(Auth.t(), String.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def firewall_nat_delete(auth, ip, id, opts \\ []) when is_binary(id) do
    delete(auth, ip, "/ip/firewall/nat/#{id}", opts)
  end

  @doc """
  Ensure a firewall NAT rule exists. By default matches by ["chain", "action"]. You can pass unique_keys: [..] in opts.
  Returns {:ok, map()} of matched keys when found or created.
  """
  @spec firewall_nat_ensure(Auth.t(), String.t(), map(), Keyword.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def firewall_nat_ensure(auth, ip, rule, opts \\ []) when is_map(rule) do
    unique_keys = Keyword.get(opts, :unique_keys, ["chain", "action"])

    with {:ok, list} <- firewall_nat_list(auth, ip, opts) do
      found =
        Enum.find(list, fn e ->
          Enum.all?(unique_keys, fn k -> Map.get(e, k) == Map.get(rule, k) end)
        end)

      if found do
        {:ok, Map.new(unique_keys, fn k -> {k, Map.get(found, k)} end)}
      else
        case firewall_nat_add(auth, ip, rule, opts) do
          {:ok, _} -> {:ok, Map.new(unique_keys, fn k -> {k, Map.get(rule, k)} end)}
          {:error, _} = err -> err
        end
      end
    end
  end

  @doc """
  PATCH /interface/{id} with attrs
  """
  @spec interface_update(Auth.t(), String.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def interface_update(auth, ip, id, attrs, opts \\ []) when is_binary(id) do
    patch(auth, ip, "/interface/#{id}", attrs, opts)
  end

  @doc """
  Ensure interface settings. Ident can be an interface name or .id. Applies only differing keys from attrs.
  Returns {:ok, %{id: id, name: name, changed: [keys]}} when up-to-date or updated; {:error, not_found} if interface not present.
  """
  @spec interface_ensure(Auth.t(), String.t(), String.t(), map(), Keyword.t()) ::
          {:ok, %{id: String.t(), name: String.t(), changed: [String.t()]}} | {:error, term()}
  def interface_ensure(auth, ip, ident, attrs, opts \\ [])
      when is_binary(ident) and is_map(attrs) do
    with {:ok, list} <- interface_list(auth, ip, opts) do
      case Enum.find(list, fn e -> e[".id"] == ident or e["name"] == ident end) do
        nil ->
          {:error, :not_found}

        entry ->
          id = entry[".id"]
          name = entry["name"]

          changed_map =
            attrs
            |> Enum.reduce(%{}, fn {k, v}, acc ->
              existing = Map.get(entry, k)

              if existing == v do
                acc
              else
                Map.put(acc, k, v)
              end
            end)

          changed_keys = Map.keys(changed_map)

          case changed_keys do
            [] ->
              {:ok, %{id: id, name: name, changed: []}}

            _ ->
              case interface_update(auth, ip, id, changed_map, opts) do
                {:ok, _} ->
                  {:ok, %{id: id, name: name, changed: Enum.map(changed_keys, &to_string/1)}}

                {:error, _} = err ->
                  err
              end
          end
      end
    end
  end

  @doc """
  Convenience: set disabled=no
  """
  @spec interface_enable(Auth.t(), String.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def interface_enable(auth, ip, id, opts \\ []) when is_binary(id) do
    interface_update(auth, ip, id, %{"disabled" => "false"}, opts)
  end

  @doc """
  Convenience: set disabled=yes
  """
  @spec interface_disable(Auth.t(), String.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def interface_disable(auth, ip, id, opts \\ []) when is_binary(id) do
    interface_update(auth, ip, id, %{"disabled" => "true"}, opts)
  end

  @doc """
  GET /ip/dhcp-server/lease
  """
  @spec dhcp_lease_list(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def dhcp_lease_list(auth, ip, opts \\ []) do
    get(auth, ip, "/ip/dhcp-server/lease", opts)
  end

  @doc """
  POST /ip/dhcp-server/lease
  """
  @spec dhcp_lease_add(Auth.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def dhcp_lease_add(auth, ip, attrs, opts \\ []) when is_map(attrs) or is_list(attrs) do
    post(auth, ip, "/ip/dhcp-server/lease", attrs, opts)
  end

  @doc """
  Ensure a DHCP lease exists. Matches by ["address", "mac-address"]. Returns {:ok, %{address: ..., mac: ...}} if found or created.
  """
  @spec dhcp_lease_ensure(Auth.t(), String.t(), map(), Keyword.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def dhcp_lease_ensure(auth, ip, attrs, opts \\ []) when is_map(attrs) do
    with {:ok, list} <- dhcp_lease_list(auth, ip, opts) do
      addr = Map.get(attrs, "address")
      mac = Map.get(attrs, "mac-address")

      if is_nil(addr) or is_nil(mac) do
        {:error,
         %Error{
           status: nil,
           reason: :invalid_argument,
           details: "address and mac-address required"
         }}
      else
        found = Enum.find(list, fn e -> e["address"] == addr and e["mac-address"] == mac end)

        if found do
          {:ok, %{address: addr, mac: mac}}
        else
          case dhcp_lease_add(auth, ip, attrs, opts) do
            {:ok, _} -> {:ok, %{address: addr, mac: mac}}
            {:error, _} = err -> err
          end
        end
      end
    end
  end

  @doc """
  PATCH /ip/dhcp-server/lease/{id}
  """
  @spec dhcp_lease_update(Auth.t(), String.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def dhcp_lease_update(auth, ip, id, attrs, opts \\ []) when is_binary(id) do
    patch(auth, ip, "/ip/dhcp-server/lease/#{id}", attrs, opts)
  end

  @doc """
  DELETE /ip/dhcp-server/lease/{id}
  """
  @spec dhcp_lease_delete(Auth.t(), String.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def dhcp_lease_delete(auth, ip, id, opts \\ []) when is_binary(id) do
    delete(auth, ip, "/ip/dhcp-server/lease/#{id}", opts)
  end

  @doc """
  GET /ip/route
  """
  @spec route_list(Auth.t(), String.t(), Keyword.t()) :: {:ok, any() | nil} | {:error, Error.t()}
  def route_list(auth, ip, opts \\ []) do
    get(auth, ip, "/ip/route", opts)
  end

  @doc """
  POST /ip/route
  """
  @spec route_add(Auth.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def route_add(auth, ip, attrs, opts \\ []) when is_map(attrs) or is_list(attrs) do
    post(auth, ip, "/ip/route", attrs, opts)
  end

  @doc """
  Ensure a route exists. Matches by ["dst-address", "gateway"]. Returns {:ok, %{dst: ..., gw: ...}} if found or created.
  """
  @spec route_ensure(Auth.t(), String.t(), map(), Keyword.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def route_ensure(auth, ip, attrs, opts \\ []) when is_map(attrs) do
    with {:ok, list} <- route_list(auth, ip, opts) do
      dst = Map.get(attrs, "dst-address")
      gw = Map.get(attrs, "gateway")

      if is_nil(dst) or is_nil(gw) do
        {:error,
         %Error{
           status: nil,
           reason: :invalid_argument,
           details: "dst-address and gateway required"
         }}
      else
        found = Enum.find(list, fn e -> e["dst-address"] == dst and e["gateway"] == gw end)

        if found do
          {:ok, %{dst: dst, gw: gw}}
        else
          case route_add(auth, ip, attrs, opts) do
            {:ok, _} -> {:ok, %{dst: dst, gw: gw}}
            {:error, _} = err -> err
          end
        end
      end
    end
  end

  @doc """
  DELETE /ip/route/{id}
  """
  @spec route_delete(Auth.t(), String.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def route_delete(auth, ip, id, opts \\ []) when is_binary(id) do
    delete(auth, ip, "/ip/route/#{id}", opts)
  end

  # Bridges

  @doc """
  GET /interface/bridge
  """
  @spec bridge_list(Auth.t(), String.t(), Keyword.t()) :: {:ok, any() | nil} | {:error, Error.t()}
  def bridge_list(auth, ip, opts \\ []) do
    get(auth, ip, "/interface/bridge", opts)
  end

  @doc """
  POST /interface/bridge
  """
  @spec bridge_add(Auth.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def bridge_add(auth, ip, attrs, opts \\ []) when is_map(attrs) or is_list(attrs) do
    post(auth, ip, "/interface/bridge", attrs, opts)
  end

  @doc """
  Ensure a bridge exists by name. Returns {:ok, name} if found or created.
  """
  @spec bridge_ensure(Auth.t(), String.t(), String.t(), map(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def bridge_ensure(auth, ip, name, attrs \\ %{}, opts \\ []) when is_binary(name) do
    with {:ok, list} <- bridge_list(auth, ip, opts) do
      case Enum.find(list, &(&1["name"] == name)) do
        nil ->
          merged = Map.put(attrs, "name", name)

          case bridge_add(auth, ip, merged, opts) do
            {:ok, _} -> {:ok, name}
            {:error, _} = err -> err
          end

        _found ->
          {:ok, name}
      end
    end
  end

  @doc """
  PATCH /interface/bridge/{id}
  """
  @spec bridge_update(Auth.t(), String.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def bridge_update(auth, ip, id, attrs, opts \\ []) when is_binary(id) do
    patch(auth, ip, "/interface/bridge/#{id}", attrs, opts)
  end

  @doc """
  DELETE /interface/bridge/{id}
  """
  @spec bridge_delete(Auth.t(), String.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def bridge_delete(auth, ip, id, opts \\ []) when is_binary(id) do
    delete(auth, ip, "/interface/bridge/#{id}", opts)
  end

  # Bridge ports

  @doc """
  GET /interface/bridge/port
  """
  @spec bridge_port_list(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def bridge_port_list(auth, ip, opts \\ []) do
    get(auth, ip, "/interface/bridge/port", opts)
  end

  @doc """
  POST /interface/bridge/port
  """
  @spec bridge_port_add(Auth.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def bridge_port_add(auth, ip, attrs, opts \\ []) when is_map(attrs) or is_list(attrs) do
    post(auth, ip, "/interface/bridge/port", attrs, opts)
  end

  @doc """
  PATCH /interface/bridge/port/{id}
  """
  @spec bridge_port_update(Auth.t(), String.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def bridge_port_update(auth, ip, id, attrs, opts \\ []) when is_binary(id) do
    patch(auth, ip, "/interface/bridge/port/#{id}", attrs, opts)
  end

  @doc """
  Ensure a bridge port exists for the given bridge and interface.
  Returns {:ok, {bridge, interface}} when found or created.
  """
  @spec bridge_port_ensure(Auth.t(), String.t(), String.t(), String.t(), map(), Keyword.t()) ::
          {:ok, {String.t(), String.t()}} | {:error, Error.t()}
  def bridge_port_ensure(auth, ip, bridge, interface, attrs \\ %{}, opts \\ [])
      when is_binary(bridge) and is_binary(interface) do
    with {:ok, list} <- bridge_port_list(auth, ip, opts) do
      found = Enum.find(list, fn e -> e["bridge"] == bridge and e["interface"] == interface end)

      if found do
        {:ok, {bridge, interface}}
      else
        merged = attrs |> Map.put("bridge", bridge) |> Map.put("interface", interface)

        case bridge_port_add(auth, ip, merged, opts) do
          {:ok, _} -> {:ok, {bridge, interface}}
          {:error, _} = err -> err
        end
      end
    end
  end

  @doc """
  DELETE /interface/bridge/port/{id}
  """
  @spec bridge_port_delete(Auth.t(), String.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def bridge_port_delete(auth, ip, id, opts \\ []) when is_binary(id) do
    delete(auth, ip, "/interface/bridge/port/#{id}", opts)
  end

  # Bridge VLANs

  @doc """
  GET /interface/bridge/vlan
  """
  @spec bridge_vlan_list(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def bridge_vlan_list(auth, ip, opts \\ []) do
    get(auth, ip, "/interface/bridge/vlan", opts)
  end

  @doc """
  POST /interface/bridge/vlan
  """
  @spec bridge_vlan_add(Auth.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def bridge_vlan_add(auth, ip, attrs, opts \\ []) when is_map(attrs) or is_list(attrs) do
    post(auth, ip, "/interface/bridge/vlan", attrs, opts)
  end

  @doc """
  Ensure a bridge VLAN entry exists for the given bridge and vlan-ids.
  Returns {:ok, {bridge, vlan_ids}} when found or created.
  """
  @spec bridge_vlan_ensure(Auth.t(), String.t(), String.t(), String.t(), map(), Keyword.t()) ::
          {:ok, {String.t(), String.t()}} | {:error, Error.t()}
  def bridge_vlan_ensure(auth, ip, bridge, vlan_ids, attrs \\ %{}, opts \\ [])
      when is_binary(bridge) and is_binary(vlan_ids) do
    case bridge_vlan_list(auth, ip, opts) do
      {:ok, list} when is_list(list) ->
        case Enum.find(list, &(&1["bridge"] == bridge and &1["vlan-ids"] == vlan_ids)) do
          nil ->
            merged = attrs |> Map.put("bridge", bridge) |> Map.put("vlan-ids", vlan_ids)

            case bridge_vlan_add(auth, ip, merged, opts) do
              {:ok, _} -> {:ok, {bridge, vlan_ids}}
              {:error, _} = err -> err
            end

          _found ->
            {:ok, {bridge, vlan_ids}}
        end

      {:error, _} = err ->
        err

      other ->
        other
    end
  end

  @doc """
  PATCH /interface/bridge/vlan/{id}
  """
  @spec bridge_vlan_update(Auth.t(), String.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def bridge_vlan_update(auth, ip, id, attrs, opts \\ []) when is_binary(id) do
    patch(auth, ip, "/interface/bridge/vlan/#{id}", attrs, opts)
  end

  @doc """
  DELETE /interface/bridge/vlan/{id}
  """
  @spec bridge_vlan_delete(Auth.t(), String.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def bridge_vlan_delete(auth, ip, id, opts \\ []) when is_binary(id) do
    delete(auth, ip, "/interface/bridge/vlan/#{id}", opts)
  end

  # Wireless (legacy wireless package)

  @doc """
  GET /interface/wireless
  """
  @spec wireless_interface_list(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def wireless_interface_list(auth, ip, opts \\ []) do
    get(auth, ip, "/interface/wireless", opts)
  end

  @doc """
  POST /interface/wireless
  """
  @spec wireless_interface_add(Auth.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def wireless_interface_add(auth, ip, attrs, opts \\ []) when is_map(attrs) or is_list(attrs) do
    post(auth, ip, "/interface/wireless", attrs, opts)
  end

  @doc """
  Ensure a legacy wireless interface exists by name.
  """
  @spec wireless_interface_ensure(Auth.t(), String.t(), String.t(), map(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def wireless_interface_ensure(auth, ip, name, attrs \\ %{}, opts \\ []) when is_binary(name) do
    with {:ok, list} <- wireless_interface_list(auth, ip, opts) do
      case Enum.find(list, &(&1["name"] == name)) do
        nil ->
          merged = Map.put(attrs, "name", name)

          case wireless_interface_add(auth, ip, merged, opts) do
            {:ok, _} -> {:ok, name}
            {:error, _} = err -> err
          end

        _found ->
          {:ok, name}
      end
    end
  end

  @doc """
  PATCH /interface/wireless/{id}
  """
  @spec wireless_interface_update(Auth.t(), String.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def wireless_interface_update(auth, ip, id, attrs, opts \\ []) when is_binary(id) do
    patch(auth, ip, "/interface/wireless/#{id}", attrs, opts)
  end

  @doc """
  DELETE /interface/wireless/{id}
  """
  @spec wireless_interface_delete(Auth.t(), String.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def wireless_interface_delete(auth, ip, id, opts \\ []) when is_binary(id) do
    delete(auth, ip, "/interface/wireless/#{id}", opts)
  end

  @doc """
  GET /interface/wireless/registration-table
  """
  @spec wireless_registration_table(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def wireless_registration_table(auth, ip, opts \\ []) do
    get(auth, ip, "/interface/wireless/registration-table", opts)
  end

  @doc """
  GET /interface/wireless/security-profiles
  """
  @spec wireless_security_profile_list(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def wireless_security_profile_list(auth, ip, opts \\ []) do
    get(auth, ip, "/interface/wireless/security-profiles", opts)
  end

  @doc """
  Ensure a legacy wireless security profile exists by name.
  """
  @spec wireless_security_profile_ensure(Auth.t(), String.t(), String.t(), map(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def wireless_security_profile_ensure(auth, ip, name, attrs \\ %{}, opts \\ [])
      when is_binary(name) do
    with {:ok, list} <- wireless_security_profile_list(auth, ip, opts) do
      case Enum.find(list, &(&1["name"] == name)) do
        nil ->
          merged = Map.put(attrs, "name", name)

          case wireless_security_profile_add(auth, ip, merged, opts) do
            {:ok, _} -> {:ok, name}
            {:error, _} = err -> err
          end

        _found ->
          {:ok, name}
      end
    end
  end

  @doc """
  POST /interface/wireless/security-profiles
  """
  @spec wireless_security_profile_add(Auth.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def wireless_security_profile_add(auth, ip, attrs, opts \\ [])
      when is_map(attrs) or is_list(attrs) do
    post(auth, ip, "/interface/wireless/security-profiles", attrs, opts)
  end

  @doc """
  PATCH /interface/wireless/security-profiles/{id}
  """
  @spec wireless_security_profile_update(
          Auth.t(),
          String.t(),
          String.t(),
          map() | list(),
          Keyword.t()
        ) :: {:ok, any() | nil} | {:error, Error.t()}
  def wireless_security_profile_update(auth, ip, id, attrs, opts \\ []) when is_binary(id) do
    patch(auth, ip, "/interface/wireless/security-profiles/#{id}", attrs, opts)
  end

  @doc """
  DELETE /interface/wireless/security-profiles/{id}
  """
  @spec wireless_security_profile_delete(Auth.t(), String.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def wireless_security_profile_delete(auth, ip, id, opts \\ []) when is_binary(id) do
    delete(auth, ip, "/interface/wireless/security-profiles/#{id}", opts)
  end

  # WiFi (wifiwave2 package)

  @doc """
  Ensure a WiFi security profile with the given name exists; returns the found or created entry name.
  If the endpoint is unavailable, returns the underlying error.
  """
  @spec wifi_security_ensure(Auth.t(), String.t(), String.t(), map(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def wifi_security_ensure(auth, ip, name, attrs \\ %{}, opts \\ []) when is_binary(name) do
    case wifi_security_list(auth, ip, opts) do
      {:ok, list} when is_list(list) ->
        case Enum.find(list, &(&1["name"] == name)) do
          nil ->
            merged = Map.put(attrs, "name", name)

            case wifi_security_add(auth, ip, merged, opts) do
              {:ok, _} -> {:ok, name}
              {:error, _} = err -> err
            end

          _found ->
            {:ok, name}
        end

      {:error, _} = err ->
        err

      other ->
        other
    end
  end

  @doc """
  Ensure a WiFi SSID with the given name exists; returns the found or created entry name.
  If the endpoint is unavailable (:wifi_ssid_unavailable), returns the underlying error.
  """
  @spec wifi_ssid_ensure(Auth.t(), String.t(), String.t(), map(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def wifi_ssid_ensure(auth, ip, name, attrs \\ %{}, opts \\ []) when is_binary(name) do
    case wifi_ssid_list(auth, ip, opts) do
      {:ok, list} when is_list(list) ->
        case Enum.find(list, &(&1["name"] == name)) do
          nil ->
            merged = Map.put(attrs, "name", name)

            case wifi_ssid_add(auth, ip, merged, opts) do
              {:ok, _} -> {:ok, name}
              {:error, _} = err -> err
            end

          _found ->
            {:ok, name}
        end

      {:error, _} = err ->
        err

      other ->
        other
    end
  end

  # ARP and Neighbors

  @doc """
  GET /ip/arp
  """
  @spec arp_list(Auth.t(), String.t(), Keyword.t()) :: {:ok, any() | nil} | {:error, Error.t()}
  def arp_list(auth, ip, opts \\ []) do
    get(auth, ip, "/ip/arp", opts)
  end

  @doc """
  GET /ip/neighbor
  """
  @spec neighbor_list(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def neighbor_list(auth, ip, opts \\ []) do
    get(auth, ip, "/ip/neighbor", opts)
  end

  # CAPsMAN

  @doc """
  POST /caps-man/security
  """
  @spec capsman_security_add(Auth.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def capsman_security_add(auth, ip, attrs, opts \\ []) when is_map(attrs) or is_list(attrs) do
    post(auth, ip, "/caps-man/security", attrs, opts)
  end

  @doc """
  Ensure a CAPsMAN security profile with the given name exists.
  """
  @spec capsman_security_ensure(Auth.t(), String.t(), String.t(), map(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def capsman_security_ensure(auth, ip, name, attrs \\ %{}, opts \\ []) when is_binary(name) do
    case capsman_security_list(auth, ip, opts) do
      {:ok, list} when is_list(list) ->
        case Enum.find(list, &(&1["name"] == name)) do
          nil ->
            merged = Map.put(attrs, "name", name)

            case capsman_security_add(auth, ip, merged, opts) do
              {:ok, _} -> {:ok, name}
              {:error, _} = err -> err
            end

          _found ->
            {:ok, name}
        end

      {:error, _} = err ->
        err

      other ->
        other
    end
  end

  @doc """
  GET /caps-man/provisioning
  """
  @spec capsman_provisioning_list(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def capsman_provisioning_list(auth, ip, opts \\ []) do
    get(auth, ip, "/caps-man/provisioning", opts)
  end

  @doc """
  POST /caps-man/provisioning
  """
  @spec capsman_provisioning_add(Auth.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def capsman_provisioning_add(auth, ip, attrs, opts \\ [])
      when is_map(attrs) or is_list(attrs) do
    post(auth, ip, "/caps-man/provisioning", attrs, opts)
  end

  @doc """
  Ensure a CAPsMAN provisioning rule exists. By default matches by ["action", "master-configuration"].
  Returns {:ok, map()} of matched keys when found or created.
  """
  @spec capsman_provisioning_ensure(Auth.t(), String.t(), map(), Keyword.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def capsman_provisioning_ensure(auth, ip, rule, opts \\ []) when is_map(rule) do
    unique_keys = Keyword.get(opts, :unique_keys, ["action", "master-configuration"])

    with {:ok, list} <- capsman_provisioning_list(auth, ip, opts) do
      found =
        Enum.find(list, fn e ->
          Enum.all?(unique_keys, fn k -> Map.get(e, k) == Map.get(rule, k) end)
        end)

      if found do
        {:ok, Map.new(unique_keys, fn k -> {k, Map.get(found, k)} end)}
      else
        case capsman_provisioning_add(auth, ip, rule, opts) do
          {:ok, _} -> {:ok, Map.new(unique_keys, fn k -> {k, Map.get(rule, k)} end)}
          {:error, _} = err -> err
        end
      end
    end
  end

  @doc """
  GET /caps-man/interface
  """
  @spec capsman_interface_list(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def capsman_interface_list(auth, ip, opts \\ []) do
    get(auth, ip, "/caps-man/interface", opts)
  end

  @doc """
  GET /caps-man/registration-table
  """
  @spec capsman_registration_table(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def capsman_registration_table(auth, ip, opts \\ []) do
    get(auth, ip, "/caps-man/registration-table", opts)
  end

  @doc """
  GET /caps-man/security
  """
  @spec capsman_security_list(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def capsman_security_list(auth, ip, opts \\ []) do
    get(auth, ip, "/caps-man/security", opts)
  end

  @doc """
  GET /interface/wifi
  """
  @spec wifi_interface_list(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def wifi_interface_list(auth, ip, opts \\ []) do
    get(auth, ip, "/interface/wifi", opts)
  end

  @doc """
  PATCH /interface/wifi/{id}
  """
  @spec wifi_interface_update(Auth.t(), String.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def wifi_interface_update(auth, ip, id, attrs, opts \\ []) when is_binary(id) do
    patch(auth, ip, "/interface/wifi/#{id}", attrs, opts)
  end

  @doc """
  GET /interface/wifi/ssid
  """
  @spec wifi_ssid_list(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def wifi_ssid_list(auth, ip, opts \\ []) do
    get(auth, ip, "/interface/wifi/ssid", opts)
  end

  @doc """
  POST /interface/wifi/ssid
  """
  @spec wifi_ssid_add(Auth.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def wifi_ssid_add(auth, ip, attrs, opts \\ []) when is_map(attrs) or is_list(attrs) do
    post(auth, ip, "/interface/wifi/ssid", attrs, opts)
  end

  @doc """
  PATCH /interface/wifi/ssid/{id}
  """
  @spec wifi_ssid_update(Auth.t(), String.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def wifi_ssid_update(auth, ip, id, attrs, opts \\ []) when is_binary(id) do
    patch(auth, ip, "/interface/wifi/ssid/#{id}", attrs, opts)
  end

  @doc """
  DELETE /interface/wifi/ssid/{id}
  """
  @spec wifi_ssid_delete(Auth.t(), String.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def wifi_ssid_delete(auth, ip, id, opts \\ []) when is_binary(id) do
    delete(auth, ip, "/interface/wifi/ssid/#{id}", opts)
  end

  @doc """
  GET /interface/wifi/security
  """
  @spec wifi_security_list(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def wifi_security_list(auth, ip, opts \\ []) do
    get(auth, ip, "/interface/wifi/security", opts)
  end

  @doc """
  POST /interface/wifi/security
  """
  @spec wifi_security_add(Auth.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def wifi_security_add(auth, ip, attrs, opts \\ []) when is_map(attrs) or is_list(attrs) do
    post(auth, ip, "/interface/wifi/security", attrs, opts)
  end

  @doc """
  PATCH /interface/wifi/security/{id}
  """
  @spec wifi_security_update(Auth.t(), String.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def wifi_security_update(auth, ip, id, attrs, opts \\ []) when is_binary(id) do
    patch(auth, ip, "/interface/wifi/security/#{id}", attrs, opts)
  end

  @doc """
  DELETE /interface/wifi/security/{id}
  """
  @spec wifi_security_delete(Auth.t(), String.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def wifi_security_delete(auth, ip, id, opts \\ []) when is_binary(id) do
    delete(auth, ip, "/interface/wifi/security/#{id}", opts)
  end

  # -- multi (concurrent batch) --

  @doc """
  Execute the same REST call concurrently across multiple IPs.

  - ips: list of target IPs (IPv4/IPv6 as strings)
  - method: :get | :post | :put | :patch | :delete
  - path: string path under /rest (e.g., "/system/resource")
  - opts: keyword options accepted by call/5 (e.g., scheme:, decode:, params:, headers:, body: for write methods)
  - stream_opts:
    - :max_concurrency (default System.schedulers_online())
    - :timeout (default 15_000 ms)

  Returns a list in input order: [%{ip: ip, result: {:ok, value} | {:error, %MikrotikApi.Error{}}}]
  """
  @spec multi(Auth.t(), [String.t()], method(), String.t(), Keyword.t(), Keyword.t()) :: [
          %{ip: String.t(), result: {:ok, any() | nil} | {:error, Error.t()}}
        ]
  def multi(%Auth{} = auth, ips, method, path, opts \\ [], stream_opts \\ []) when is_list(ips) do
    max_conc = Keyword.get(stream_opts, :max_concurrency, System.schedulers_online())
    timeout = Keyword.get(stream_opts, :timeout, 15_000)

    owner = self()

    ips
    |> Task.async_stream(
      fn ip ->
        {ip, call(auth, ip, method, path, Keyword.put(opts, :owner_pid, owner))}
      end,
      max_concurrency: max_conc,
      timeout: timeout,
      ordered: true
    )
    |> Enum.map(fn
      {:ok, {ip, res}} ->
        %{ip: ip, result: res}

      {:exit, reason} ->
        %{ip: nil, result: {:error, %Error{status: nil, reason: :task_exit, details: reason}}}
    end)
  end

  # -- telemetry helpers (Phase 1: operations essentials) --

  @doc """
  GET /system/health
  """
  @spec system_health(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def system_health(auth, ip, opts \\ []) do
    get(auth, ip, "/system/health", opts)
  end

  @doc """
  GET /system/package
  """
  @spec system_packages(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def system_packages(auth, ip, opts \\ []) do
    get(auth, ip, "/system/package", opts)
  end

  @doc """
  GET /ip/firewall/connection
  """
  @spec firewall_connection_list(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def firewall_connection_list(auth, ip, opts \\ []) do
    get(auth, ip, "/ip/firewall/connection", opts)
  end

  @doc """
  GET /ip/dns (config/stats)
  """
  @spec dns_config(Auth.t(), String.t(), Keyword.t()) :: {:ok, any() | nil} | {:error, Error.t()}
  def dns_config(auth, ip, opts \\ []) do
    get(auth, ip, "/ip/dns", opts)
  end

  @doc """
  GET /ip/dns/cache
  """
  @spec dns_cache_list(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def dns_cache_list(auth, ip, opts \\ []) do
    get(auth, ip, "/ip/dns/cache", opts)
  end

  @doc """
  GET /ip/pool
  """
  @spec ip_pool_list(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def ip_pool_list(auth, ip, opts \\ []) do
    get(auth, ip, "/ip/pool", opts)
  end

  @doc """
  GET /ip/firewall/address-list
  """
  @spec firewall_address_list(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def firewall_address_list(auth, ip, opts \\ []) do
    get(auth, ip, "/ip/firewall/address-list", opts)
  end

  # -- IPv6 parity helpers (Phase 2) --

  @doc """
  GET /ipv6/route
  """
  @spec ipv6_route_list(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def ipv6_route_list(auth, ip, opts \\ []) do
    get(auth, ip, "/ipv6/route", opts)
  end

  @doc """
  GET /ipv6/pool
  """
  @spec ipv6_pool_list(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def ipv6_pool_list(auth, ip, opts \\ []) do
    get(auth, ip, "/ipv6/pool", opts)
  end

  @doc """
  GET /ipv6/firewall/filter
  """
  @spec ipv6_firewall_filter_list(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def ipv6_firewall_filter_list(auth, ip, opts \\ []) do
    get(auth, ip, "/ipv6/firewall/filter", opts)
  end

  @doc """
  GET /ipv6/neighbor
  """
  @spec ipv6_neighbor_list(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def ipv6_neighbor_list(auth, ip, opts \\ []) do
    get(auth, ip, "/ipv6/neighbor", opts)
  end

  @doc """
  GET /ipv6/firewall/address-list
  """
  @spec ipv6_firewall_address_list(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def ipv6_firewall_address_list(auth, ip, opts \\ []) do
    get(auth, ip, "/ipv6/firewall/address-list", opts)
  end

  # -- extended telemetry helpers (Phase 4) --

  @doc """
  GET /interface/ethernet/poe
  """
  @spec ethernet_poe_list(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def ethernet_poe_list(auth, ip, opts \\ []) do
    get(auth, ip, "/interface/ethernet/poe", opts)
  end

  @doc """
  GET /interface/ethernet/monitor/{ident}
  """
  @spec interface_ethernet_monitor(Auth.t(), String.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def interface_ethernet_monitor(auth, ip, ident, opts \\ []) when is_binary(ident) do
    get(auth, ip, "/interface/ethernet/monitor/#{ident}", opts)
  end

  @doc """
  GET /tool/netwatch
  """
  @spec tool_netwatch_list(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def tool_netwatch_list(auth, ip, opts \\ []) do
    get(auth, ip, "/tool/netwatch", opts)
  end

  @doc """
  GET /ip/cloud
  """
  @spec ip_cloud_info(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def ip_cloud_info(auth, ip, opts \\ []) do
    get(auth, ip, "/ip/cloud", opts)
  end

  @doc """
  GET /interface/eoip
  """
  @spec eoip_list(Auth.t(), String.t(), Keyword.t()) :: {:ok, any() | nil} | {:error, Error.t()}
  def eoip_list(auth, ip, opts \\ []) do
    get(auth, ip, "/interface/eoip", opts)
  end

  @doc """
  GET /interface/gre
  """
  @spec gre_list(Auth.t(), String.t(), Keyword.t()) :: {:ok, any() | nil} | {:error, Error.t()}
  def gre_list(auth, ip, opts \\ []) do
    get(auth, ip, "/interface/gre", opts)
  end

  @doc """
  GET /interface/ipip
  """
  @spec ipip_list(Auth.t(), String.t(), Keyword.t()) :: {:ok, any() | nil} | {:error, Error.t()}
  def ipip_list(auth, ip, opts \\ []) do
    get(auth, ip, "/interface/ipip", opts)
  end

  @doc """
  GET /interface/ethernet/switch/port
  """
  @spec ethernet_switch_port_list(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def ethernet_switch_port_list(auth, ip, opts \\ []) do
    get(auth, ip, "/interface/ethernet/switch/port", opts)
  end

  @doc """
  GET /user/active
  """
  @spec user_active_list(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def user_active_list(auth, ip, opts \\ []) do
    get(auth, ip, "/user/active", opts)
  end

  @doc """
  GET /queue/simple
  """
  @spec queue_simple_list(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def queue_simple_list(auth, ip, opts \\ []) do
    get(auth, ip, "/queue/simple", opts)
  end

  @doc """
  GET /queue/tree
  """
  @spec queue_tree_list(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def queue_tree_list(auth, ip, opts \\ []) do
    get(auth, ip, "/queue/tree", opts)
  end

  @doc """
  GET /routing/bfd/session
  """
  @spec routing_bfd_list(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def routing_bfd_list(auth, ip, opts \\ []) do
    get(auth, ip, "/routing/bfd/session", opts)
  end

  @doc """
  GET /routing/bgp/session
  """
  @spec routing_bgp_list(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def routing_bgp_list(auth, ip, opts \\ []) do
    get(auth, ip, "/routing/bgp/session", opts)
  end

  @doc """
  GET /routing/stats
  """
  @spec routing_stats(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def routing_stats(auth, ip, opts \\ []) do
    get(auth, ip, "/routing/stats", opts)
  end

  @doc """
  GET /certificate
  """
  @spec certificate_list(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def certificate_list(auth, ip, opts \\ []) do
    get(auth, ip, "/certificate", opts)
  end

  @doc """
  GET /container
  """
  @spec container_list(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def container_list(auth, ip, opts \\ []) do
    get(auth, ip, "/container", opts)
  end

  # -- probe helpers --

  @doc """
  Probe core device info and summarize.

  Returns a map with keys:
  - system: {:ok, map()} | {:error, error_summary}
  - counts: %{interfaces: n | nil, ip_addresses: n | nil, arp: n | nil, neighbors: n | nil}

  Accepts same opts as other calls (e.g., scheme: :http | :https).
  """
  @spec probe_device(Auth.t(), String.t(), Keyword.t()) :: {:ok, map()} | {:error, Error.t()}
  def probe_device(%Auth{} = auth, ip, opts \\ []) when is_binary(ip) do
    sys = system_resource(auth, ip, opts)
    ifs = interface_list(auth, ip, opts)
    ips = ip_address_list(auth, ip, opts)
    arp = arp_list(auth, ip, opts)
    nbr = neighbor_list(auth, ip, opts)

    {:ok,
     %{
       system:
         case sys do
           {:ok, m} when is_map(m) ->
             {:ok,
              %{
                "board-name" => Map.get(m, "board-name"),
                "version" => Map.get(m, "version"),
                "platform" => Map.get(m, "platform")
              }}

           {:ok, other} ->
             {:ok, other}

           {:error, %Error{} = e} ->
             error_summary(e)
         end,
       counts: %{
         interfaces: list_count(ifs),
         ip_addresses: list_count(ips),
         arp: list_count(arp),
         neighbors: list_count(nbr)
       }
     }}
  end

  defp list_count({:ok, list}) when is_list(list), do: length(list)
  defp list_count({:ok, _}), do: nil
  defp list_count({:error, _}), do: nil

  defp error_summary(%Error{status: code, reason: reason}),
    do: {:error, %{status_code: code, reason: reason}}

  @doc """
  Probe wireless (legacy) and wifi (wifiwave2) endpoint availability and summarize.

  Returns a map with sections :wireless and :wifi, each containing endpoint keys
  and status maps like %{status: :ok | :unavailable | :error, count: non_neg_integer | nil, reason: term() | nil, status_code: integer | nil}.

  Accepts the same opts as other calls (e.g., scheme: :http | :https).
  """
  @spec probe_wireless(Auth.t(), String.t(), Keyword.t()) :: {:ok, map()} | {:error, Error.t()}
  def probe_wireless(%Auth{} = auth, ip, opts \\ []) when is_binary(ip) do
    w_int = wireless_interface_list(auth, ip, opts)
    w_reg = wireless_registration_table(auth, ip, opts)
    w_sec = wireless_security_profile_list(auth, ip, opts)

    wf_int = wifi_interface_list(auth, ip, opts)
    wf_ssid = wifi_ssid_list(auth, ip, opts)
    wf_sec = wifi_security_list(auth, ip, opts)

    {:ok,
     %{
       wireless: %{
         interfaces: probe_status(w_int),
         registration_table: probe_status(w_reg),
         security_profiles: probe_status(w_sec)
       },
       wifi: %{
         interfaces: probe_status(wf_int),
         ssid: probe_status(wf_ssid),
         security: probe_status(wf_sec)
       }
     }}
  end

  defp probe_status({:ok, list}) when is_list(list), do: %{status: :ok, count: length(list)}
  defp probe_status({:ok, _other}), do: %{status: :ok, count: nil}

  defp probe_status({:error, %Error{reason: :wifi_ssid_unavailable} = _e}),
    do: %{status: :unavailable, reason: :wifi_ssid_unavailable}

  defp probe_status({:error, %Error{status: code, reason: reason}}),
    do: %{status: :error, status_code: code, reason: reason}

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
            _ -> JSON.encode!(body_term)
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
    base_ssl =
      case auth.verify do
        :verify_none ->
          [verify: :verify_none]

        _ ->
          cacerts = default_cacerts()

          if has_user_cacert_option?(auth.ssl_opts) do
            [verify: :verify_peer]
          else
            [verify: :verify_peer, cacerts: cacerts]
          end
      end

    ssl_opts = Keyword.merge(base_ssl, auth.ssl_opts)

    [
      ssl: ssl_opts,
      connect_timeout: auth.connect_timeout,
      timeout: auth.recv_timeout
    ]
  end

  defp handle_response(status, body, _opts)
       when status in 200..299 and (body == "" or status == 204) do
    {:ok, nil}
  end

  defp handle_response(status, body, opts) when status in 200..299 do
    if Keyword.get(opts, :decode, true) do
      case JSON.decode(body) do
        {:ok, data} ->
          {:ok, data}

        {:error, reason} ->
          {:error, %Error{status: status, reason: :decode_error, details: reason}}
      end
    else
      {:ok, body}
    end
  end

  defp handle_response(status, body, opts) do
    path = Keyword.get(opts, :_path)

    cond do
      status == 500 and is_binary(path) and String.starts_with?(path, "/interface/wifi/ssid") ->
        {:error, %Error{status: status, reason: :wifi_ssid_unavailable, details: truncate(body)}}

      true ->
        {:error, %Error{status: status, reason: :http_error, details: truncate(body)}}
    end
  end

  defp has_user_cacert_option?(opts) do
    Keyword.has_key?(opts, :cacerts) or Keyword.has_key?(opts, :cacertfile)
  end

  defp default_cacerts do
    try do
      :public_key.cacerts_get()
    rescue
      _ -> []
    end
  end

  defp truncate(bin) when is_binary(bin) and byte_size(bin) > 4096, do: binary_part(bin, 0, 4096)
  defp truncate(bin), do: bin

  defp monotonic_ms_since(started) do
    System.convert_time_unit(System.monotonic_time() - started, :native, :millisecond)
  end
end
