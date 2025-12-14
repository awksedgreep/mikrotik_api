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
  GET /system/identity
  """
  @spec system_identity(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def system_identity(auth, ip, opts \\ []) do
    get(auth, ip, "/system/identity", opts)
  end

  @doc """
  POST /system/identity/set - update the system identity (router name).
  """
  @spec system_identity_set(Auth.t(), String.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def system_identity_set(auth, ip, name, opts \\ []) when is_binary(name) do
    post(auth, ip, "/system/identity/set", %{"name" => name}, opts)
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
  PUT /ip/address - create an IP address.
  RouterOS REST API uses PUT for creating resources.
  """
  @spec ip_address_add(Auth.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def ip_address_add(auth, ip, attrs, opts \\ []) when is_map(attrs) or is_list(attrs) do
    put(auth, ip, "/ip/address", attrs, opts)
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
  PUT /ip/firewall/filter - create a firewall filter rule.
  RouterOS REST API uses PUT for creating resources.
  """
  @spec firewall_filter_add(Auth.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def firewall_filter_add(auth, ip, rule, opts \\ []) when is_map(rule) or is_list(rule) do
    put(auth, ip, "/ip/firewall/filter", rule, opts)
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
  PUT /ip/firewall/nat - create a firewall NAT rule.
  RouterOS REST API uses PUT for creating resources.
  """
  @spec firewall_nat_add(Auth.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def firewall_nat_add(auth, ip, rule, opts \\ []) when is_map(rule) or is_list(rule) do
    put(auth, ip, "/ip/firewall/nat", rule, opts)
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
  PUT /ip/dhcp-server/lease - create a DHCP lease.
  RouterOS REST API uses PUT for creating resources.
  """
  @spec dhcp_lease_add(Auth.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def dhcp_lease_add(auth, ip, attrs, opts \\ []) when is_map(attrs) or is_list(attrs) do
    put(auth, ip, "/ip/dhcp-server/lease", attrs, opts)
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
  PUT /ip/route - create a route.
  RouterOS REST API uses PUT for creating resources.
  """
  @spec route_add(Auth.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def route_add(auth, ip, attrs, opts \\ []) when is_map(attrs) or is_list(attrs) do
    put(auth, ip, "/ip/route", attrs, opts)
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
  PUT /interface/bridge - create a bridge interface.
  RouterOS REST API uses PUT for creating resources.
  """
  @spec bridge_add(Auth.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def bridge_add(auth, ip, attrs, opts \\ []) when is_map(attrs) or is_list(attrs) do
    put(auth, ip, "/interface/bridge", attrs, opts)
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
  PUT /interface/bridge/port - create a bridge port.
  RouterOS REST API uses PUT for creating resources.
  """
  @spec bridge_port_add(Auth.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def bridge_port_add(auth, ip, attrs, opts \\ []) when is_map(attrs) or is_list(attrs) do
    put(auth, ip, "/interface/bridge/port", attrs, opts)
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
  PUT /interface/bridge/vlan - create a bridge VLAN entry.
  RouterOS REST API uses PUT for creating resources.
  """
  @spec bridge_vlan_add(Auth.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def bridge_vlan_add(auth, ip, attrs, opts \\ []) when is_map(attrs) or is_list(attrs) do
    put(auth, ip, "/interface/bridge/vlan", attrs, opts)
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
  PUT /interface/wireless - create a wireless interface.
  RouterOS REST API uses PUT for creating resources.
  """
  @spec wireless_interface_add(Auth.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def wireless_interface_add(auth, ip, attrs, opts \\ []) when is_map(attrs) or is_list(attrs) do
    put(auth, ip, "/interface/wireless", attrs, opts)
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
  PUT /interface/wireless/security-profiles - create a wireless security profile.
  RouterOS REST API uses PUT for creating resources.
  """
  @spec wireless_security_profile_add(Auth.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def wireless_security_profile_add(auth, ip, attrs, opts \\ [])
      when is_map(attrs) or is_list(attrs) do
    put(auth, ip, "/interface/wireless/security-profiles", attrs, opts)
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
  PUT /caps-man/security - create a CAPsMAN security profile.
  RouterOS REST API uses PUT for creating resources.
  """
  @spec capsman_security_add(Auth.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def capsman_security_add(auth, ip, attrs, opts \\ []) when is_map(attrs) or is_list(attrs) do
    put(auth, ip, "/caps-man/security", attrs, opts)
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
  PUT /caps-man/provisioning - create a CAPsMAN provisioning rule.
  RouterOS REST API uses PUT for creating resources.
  """
  @spec capsman_provisioning_add(Auth.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def capsman_provisioning_add(auth, ip, attrs, opts \\ [])
      when is_map(attrs) or is_list(attrs) do
    put(auth, ip, "/caps-man/provisioning", attrs, opts)
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
  PUT /interface/wifi/ssid - create a WiFi SSID.
  RouterOS REST API uses PUT for creating resources.
  """
  @spec wifi_ssid_add(Auth.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def wifi_ssid_add(auth, ip, attrs, opts \\ []) when is_map(attrs) or is_list(attrs) do
    put(auth, ip, "/interface/wifi/ssid", attrs, opts)
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
  PUT /interface/wifi/security - create a WiFi security profile.
  RouterOS REST API uses PUT for creating resources.
  """
  @spec wifi_security_add(Auth.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def wifi_security_add(auth, ip, attrs, opts \\ []) when is_map(attrs) or is_list(attrs) do
    put(auth, ip, "/interface/wifi/security", attrs, opts)
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

  # WireGuard interfaces

  @doc """
  GET /interface/wireguard
  """
  @spec wireguard_interface_list(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def wireguard_interface_list(auth, ip, opts \\ []) do
    get(auth, ip, "/interface/wireguard", opts)
  end

  @doc """
  POST /interface/wireguard/getall with a .proplist to retrieve fields like private-key and public-key.
  """
  @spec wireguard_interface_getall(Auth.t(), String.t(), String.t(), Keyword.t()) ::
          {:ok, [map()]} | {:error, Error.t()}
  def wireguard_interface_getall(auth, ip, proplist \\ "name,private-key,public-key", opts \\ []) do
    body = %{".proplist" => proplist}
    post(auth, ip, "/interface/wireguard/getall", body, opts)
  end

  @doc """
  PUT /interface/wireguard - create a WireGuard interface.
  RouterOS REST API uses PUT for creating resources.
  Falls back to POST /interface/wireguard/add on older RouterOS versions.
  """
  @spec wireguard_interface_add(Auth.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def wireguard_interface_add(auth, ip, attrs, opts \\ []) when is_map(attrs) or is_list(attrs) do
    case put(auth, ip, "/interface/wireguard", attrs, opts) do
      {:ok, _} = ok ->
        ok

      {:error, %Error{status: 400, details: det}} = err ->
        if is_binary(det) and String.contains?(det, "no such command") do
          post(auth, ip, "/interface/wireguard/add", attrs, opts)
        else
          err
        end

      other ->
        other
    end
  end

  @doc """
  PATCH /interface/wireguard/{id}
  """
  @spec wireguard_interface_update(Auth.t(), String.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def wireguard_interface_update(auth, ip, id, attrs, opts \\ []) when is_binary(id) do
    patch(auth, ip, "/interface/wireguard/#{id}", attrs, opts)
  end

  @doc """
  DELETE /interface/wireguard/{id}
  """
  @spec wireguard_interface_delete(Auth.t(), String.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def wireguard_interface_delete(auth, ip, id, opts \\ []) when is_binary(id) do
    delete(auth, ip, "/interface/wireguard/#{id}", opts)
  end

  # WireGuard peers

  @doc """
  GET /interface/wireguard/peers
  """
  @spec wireguard_peer_list(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def wireguard_peer_list(auth, ip, opts \\ []) do
    get(auth, ip, "/interface/wireguard/peers", opts)
  end

  @doc """
  PUT /interface/wireguard/peers - create a WireGuard peer.
  RouterOS REST API uses PUT for creating resources.
  Falls back to POST /interface/wireguard/peers/add on older RouterOS versions.
  """
  @spec wireguard_peer_add(Auth.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def wireguard_peer_add(auth, ip, attrs, opts \\ []) when is_map(attrs) or is_list(attrs) do
    case put(auth, ip, "/interface/wireguard/peers", attrs, opts) do
      {:ok, _} = ok ->
        ok

      {:error, %Error{status: 400, details: det}} = err ->
        if is_binary(det) and String.contains?(det, "no such command") do
          post(auth, ip, "/interface/wireguard/peers/add", attrs, opts)
        else
          err
        end

      other ->
        other
    end
  end

  @doc """
  PATCH /interface/wireguard/peers/{id}
  """
  @spec wireguard_peer_update(Auth.t(), String.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def wireguard_peer_update(auth, ip, id, attrs, opts \\ []) when is_binary(id) do
    patch(auth, ip, "/interface/wireguard/peers/#{id}", attrs, opts)
  end

  @doc """
  DELETE /interface/wireguard/peers/{id}
  """
  @spec wireguard_peer_delete(Auth.t(), String.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def wireguard_peer_delete(auth, ip, id, opts \\ []) when is_binary(id) do
    delete(auth, ip, "/interface/wireguard/peers/#{id}", opts)
  end

  @doc """
  Ensure a WireGuard peer identified by {interface, public-key} exists with desired attributes.
  Only differing keys are patched.
  Returns {:ok, %{id: id | public-key, interface: name, changed: [keys]}}.
  """
  @spec wireguard_peer_ensure(Auth.t(), String.t(), String.t(), String.t(), map(), Keyword.t()) ::
          {:ok, %{id: String.t() | nil, interface: String.t(), changed: [String.t()]}}
          | {:error, term()}
  def wireguard_peer_ensure(auth, ip, interface, public_key, attrs \\ %{}, opts \\ [])
      when is_binary(interface) and is_binary(public_key) and is_map(attrs) do
    with {:ok, list} <- wireguard_peer_list(auth, ip, opts) do
      entry =
        Enum.find(list || [], fn e ->
          e["interface"] == interface and e["public-key"] == public_key
        end)

      case entry do
        nil ->
          merged = attrs |> Map.put("interface", interface) |> Map.put("public-key", public_key)

          case wireguard_peer_add(auth, ip, merged, opts) do
            {:ok, _} ->
              {:ok,
               %{
                 id: public_key,
                 interface: interface,
                 changed: Enum.map(Map.keys(merged), &to_string/1)
               }}

            {:error, _} = err ->
              err
          end

        %{".id" => id} = existing ->
          changed_map =
            attrs
            |> Enum.reduce(%{}, fn {k, v}, acc ->
              existing_v = Map.get(existing, k)
              if existing_v == v, do: acc, else: Map.put(acc, k, v)
            end)

          case Map.keys(changed_map) do
            [] ->
              {:ok, %{id: id, interface: interface, changed: []}}

            keys ->
              case wireguard_peer_update(auth, ip, id, changed_map, opts) do
                {:ok, _} ->
                  {:ok, %{id: id, interface: interface, changed: Enum.map(keys, &to_string/1)}}

                {:error, _} = err ->
                  err
              end
          end
      end
    end
  end

  @doc """
  Ensure a WireGuard interface by name. If present, patches only differing keys.
  Returns {:ok, %{id: id | name, name: name, changed: [keys]}} when up-to-date or updated; {:error, not_found} if list fails.
  Note: On create, the actual .id may not be known immediately; id will fallback to the provided name.
  """
  @spec wireguard_interface_ensure(Auth.t(), String.t(), String.t(), map(), Keyword.t()) ::
          {:ok, %{id: String.t(), name: String.t(), changed: [String.t()]}} | {:error, term()}
  def wireguard_interface_ensure(auth, ip, ident, attrs \\ %{}, opts \\ [])
      when is_binary(ident) and is_map(attrs) do
    with {:ok, list} <- wireguard_interface_list(auth, ip, opts) do
      case Enum.find(list, fn e -> e[".id"] == ident or e["name"] == ident end) do
        nil ->
          merged = Map.put(attrs, "name", ident)

          case wireguard_interface_add(auth, ip, merged, opts) do
            {:ok, _} ->
              {:ok, %{id: ident, name: ident, changed: Enum.map(Map.keys(merged), &to_string/1)}}

            {:error, _} = err ->
              err
          end

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
              case wireguard_interface_update(auth, ip, id, changed_map, opts) do
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
  Create a WireGuard interface on router A, then replicate its private key to router B.

  Sequential steps (no concurrency):
  1) Ensure interface on A with provided attrs (RouterOS may generate private-key).
  2) Read back interface list on A; locate the entry by name and extract "private-key".
     - If not present, returns {:error, %MikrotikApi.Error{reason: :wireguard_private_key_unreadable}}.
  3) Ensure interface on B with the same "private-key" plus provided attrs.

  Security: Never logs the private key. The returned value does not include the key.
  """
  @spec ensure_wireguard_pair(
          Auth.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          map(),
          Keyword.t()
        ) :: {:ok, %{a: map(), b: map()}} | {:error, Error.t() | term()}
  def ensure_wireguard_pair(%Auth{} = auth, ip_a, name_a, ip_b, name_b, attrs \\ %{}, opts \\ [])
      when is_binary(ip_a) and is_binary(name_a) and is_binary(ip_b) and is_binary(name_b) and
             is_map(attrs) do
    # Ensure on A without sending private-key to allow RouterOS to auto-generate when creating
    attrs_a = Map.delete(attrs, "private-key")

    with {:ok, res_a} <- wireguard_interface_ensure(auth, ip_a, name_a, attrs_a, opts),
         {:ok, list_a} <- wireguard_interface_list(auth, ip_a, opts),
         entry_a when is_map(entry_a) <-
           Enum.find(list_a, &(&1["name"] == name_a)) ||
             {:error,
              %Error{
                status: nil,
                reason: :wireguard_private_key_unreadable,
                details: "wireguard interface not found after ensure"
              }},
         key_or_nil <- Map.get(entry_a, "private-key"),
         key <-
           (if is_binary(key_or_nil) do
              key_or_nil
            else
              case wireguard_interface_getall(auth, ip_a, "name,private-key", opts) do
                {:ok, all} when is_list(all) ->
                  case Enum.find(all, &(&1["name"] == name_a)) do
                    %{"private-key" => k} when is_binary(k) -> k
                    _ -> nil
                  end

                _ ->
                  nil
              end
            end),
         key when is_binary(key) <-
           key ||
             {:error,
              %Error{
                status: nil,
                reason: :wireguard_private_key_unreadable,
                details: "RouterOS REST did not return private-key"
              }},
         attrs_b <- Map.put(attrs, "private-key", key),
         {:ok, res_b} <- wireguard_interface_ensure(auth, ip_b, name_b, attrs_b, opts) do
      {:ok, %{a: res_a, b: res_b}}
    else
      {:error, %Error{} = e} -> {:error, e}
      {:error, reason} -> {:error, reason}
      other -> other
    end
  end

  @doc """
  Create a WireGuard interface across a cluster of routers.

  Workflow:
  - Choose the first router in the list as the primary (key source).
  - Ensure the interface on the primary WITHOUT sending a private-key (allow RouterOS to auto-generate).
  - Retrieve the private-key (and public-key) from the primary; falls back to getall if list omits it.
  - Ensure the interface with the same private-key on all other routers concurrently.

  Returns {:ok, %{primary: %{ip: ip, result: map()}, members: [%{ip: ip, result: {:ok, map()} | {:error, %MikrotikApi.Error{}}}], public_key: String.t()}} on success.
  """
  @spec wireguard_cluster_add(Auth.t(), [String.t()], String.t(), map(), Keyword.t()) ::
          {:ok,
           %{
             primary: %{ip: String.t(), result: map()},
             members: [%{ip: String.t(), result: {:ok, map()} | {:error, Error.t()}}],
             public_key: String.t()
           }}
          | {:error, Error.t() | term()}
  def wireguard_cluster_add(
        %Auth{} = auth,
        [primary_ip | rest_ips] = ips,
        name,
        attrs \\ %{},
        opts \\ []
      )
      when is_list(ips) and is_binary(name) and is_map(attrs) do
    attrs_primary = Map.delete(attrs, "private-key")

    with {:ok, res_primary} <-
           wireguard_interface_ensure(auth, primary_ip, name, attrs_primary, opts),
         {:ok, list_primary} <- wireguard_interface_list(auth, primary_ip, opts),
         entry when is_map(entry) <-
           Enum.find(list_primary, &(&1["name"] == name)) ||
             {:error,
              %Error{
                status: nil,
                reason: :wireguard_private_key_unreadable,
                details: "wireguard interface not found on primary after ensure"
              }},
         key_or_nil <- Map.get(entry, "private-key"),
         key <-
           (if is_binary(key_or_nil) do
              key_or_nil
            else
              case wireguard_interface_getall(
                     auth,
                     primary_ip,
                     "name,private-key,public-key",
                     opts
                   ) do
                {:ok, all} when is_list(all) ->
                  case Enum.find(all, &(&1["name"] == name)) do
                    %{"private-key" => k} when is_binary(k) -> k
                    _ -> nil
                  end

                _ ->
                  nil
              end
            end),
         key when is_binary(key) <-
           key ||
             {:error,
              %Error{
                status: nil,
                reason: :wireguard_private_key_unreadable,
                details: "RouterOS REST did not return private-key on primary"
              }},
         pub <-
           (case wireguard_interface_getall(auth, primary_ip, "name,public-key", opts) do
              {:ok, all} when is_list(all) ->
                case Enum.find(all, &(&1["name"] == name)) do
                  %{"public-key" => pk} when is_binary(pk) -> pk
                  _ -> nil
                end

              _ ->
                nil
            end) do
      attrs_members = Map.put(attrs, "private-key", key)

      members =
        rest_ips
        |> Task.async_stream(
          fn ip ->
            {ip, wireguard_interface_ensure(auth, ip, name, attrs_members, opts)}
          end,
          max_concurrency: Keyword.get(opts, :max_concurrency, System.schedulers_online()),
          timeout: Keyword.get(opts, :timeout, 15_000),
          ordered: true
        )
        |> Enum.map(fn
          {:ok, {ip, result}} ->
            %{ip: ip, result: result}

          {:exit, reason} ->
            %{ip: nil, result: {:error, %Error{status: nil, reason: :task_exit, details: reason}}}
        end)

      {:ok, %{primary: %{ip: primary_ip, result: res_primary}, members: members, public_key: pub}}
    else
      {:error, %Error{} = e} -> {:error, e}
      {:error, reason} -> {:error, reason}
      other -> other
    end
  end

  @doc """
  Add or update WireGuard peers across a cluster on an existing interface.

  - ips: list of router IPs (all members to apply peers to)
  - name: wireguard interface name (e.g., "wg0"); will be set on each peer attrs
  - peers: list of peer maps, each requiring at least "public-key"; optional keys include
    "allowed-address", "endpoint-address", "endpoint-port", "persistent-keepalive", etc.

  Returns {:ok, [%{ip: ip, results: [result_per_peer]}]}.
  """
  @spec wireguard_cluster_add_peers(Auth.t(), [String.t()], String.t(), [map()], Keyword.t()) ::
          {:ok, [%{ip: String.t(), results: [{:ok, map()} | {:error, Error.t() | term()}]}]}
          | {:error, term()}
  def wireguard_cluster_add_peers(%Auth{} = auth, ips, name, peers, opts \\ [])
      when is_list(ips) and is_binary(name) and is_list(peers) do
    results =
      ips
      |> Task.async_stream(
        fn ip ->
          peer_results =
            Enum.map(peers, fn peer ->
              case Map.fetch(peer, "public-key") do
                {:ok, pk} when is_binary(pk) ->
                  attrs = peer |> Map.put("interface", name) |> Map.delete("public-key")
                  wireguard_peer_ensure(auth, ip, name, pk, attrs, opts)

                _ ->
                  {:error,
                   %Error{
                     status: nil,
                     reason: :invalid_argument,
                     details: "peer missing public-key"
                   }}
              end
            end)

          %{ip: ip, results: peer_results}
        end,
        max_concurrency: Keyword.get(opts, :max_concurrency, System.schedulers_online()),
        timeout: Keyword.get(opts, :timeout, 15_000),
        ordered: true
      )
      |> Enum.map(fn
        {:ok, res} ->
          res

        {:exit, reason} ->
          %{
            ip: nil,
            results: [{:error, %Error{status: nil, reason: :task_exit, details: reason}}]
          }
      end)

    {:ok, results}
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
  GET /ip/dns - alias for dns_config for consistency with REST pattern.
  """
  @spec dns_settings_get(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def dns_settings_get(auth, ip, opts \\ []) do
    get(auth, ip, "/ip/dns", opts)
  end

  @doc """
  POST /ip/dns/set - update DNS server settings.
  """
  @spec dns_settings_set(Auth.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def dns_settings_set(auth, ip, attrs, opts \\ []) when is_map(attrs) or is_list(attrs) do
    post(auth, ip, "/ip/dns/set", attrs, opts)
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
  POST /ip/dns/cache/flush - flush the DNS cache.
  """
  @spec dns_cache_flush(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def dns_cache_flush(auth, ip, opts \\ []) do
    post(auth, ip, "/ip/dns/cache/flush", %{}, opts)
  end

  # DNS Static Records

  @doc """
  GET /ip/dns/static
  """
  @spec dns_static_list(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def dns_static_list(auth, ip, opts \\ []) do
    get(auth, ip, "/ip/dns/static", opts)
  end

  @doc """
  PUT /ip/dns/static - create a DNS static record.
  RouterOS REST API uses PUT for creating resources.
  """
  @spec dns_static_add(Auth.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def dns_static_add(auth, ip, attrs, opts \\ []) when is_map(attrs) or is_list(attrs) do
    put(auth, ip, "/ip/dns/static", attrs, opts)
  end

  @doc """
  PATCH /ip/dns/static/{id}
  """
  @spec dns_static_update(Auth.t(), String.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def dns_static_update(auth, ip, id, attrs, opts \\ []) when is_binary(id) do
    patch(auth, ip, "/ip/dns/static/#{id}", attrs, opts)
  end

  @doc """
  DELETE /ip/dns/static/{id}
  """
  @spec dns_static_delete(Auth.t(), String.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def dns_static_delete(auth, ip, id, opts \\ []) when is_binary(id) do
    delete(auth, ip, "/ip/dns/static/#{id}", opts)
  end

  @doc """
  Ensure a DNS static record exists by name. If present, patches only differing keys.
  Returns {:ok, %{id: id | name, name: name, changed: [keys]}}.
  """
  @spec dns_static_ensure(Auth.t(), String.t(), String.t(), map(), Keyword.t()) ::
          {:ok, %{id: String.t(), name: String.t(), changed: [String.t()]}} | {:error, term()}
  def dns_static_ensure(auth, ip, name, attrs \\ %{}, opts \\ [])
      when is_binary(name) and is_map(attrs) do
    with {:ok, list} <- dns_static_list(auth, ip, opts) do
      case Enum.find(list || [], fn e -> e[".id"] == name or e["name"] == name end) do
        nil ->
          merged = Map.put(attrs, "name", name)

          case dns_static_add(auth, ip, merged, opts) do
            {:ok, _} ->
              {:ok, %{id: name, name: name, changed: Enum.map(Map.keys(merged), &to_string/1)}}

            {:error, _} = err ->
              err
          end

        %{".id" => id} = existing ->
          record_name = Map.get(existing, "name", name)

          changed_map =
            attrs
            |> Enum.reduce(%{}, fn {k, v}, acc ->
              existing_v = Map.get(existing, k)
              if existing_v == v, do: acc, else: Map.put(acc, k, v)
            end)

          case Map.keys(changed_map) do
            [] ->
              {:ok, %{id: id, name: record_name, changed: []}}

            keys ->
              case dns_static_update(auth, ip, id, changed_map, opts) do
                {:ok, _} ->
                  {:ok, %{id: id, name: record_name, changed: Enum.map(keys, &to_string/1)}}

                {:error, _} = err ->
                  err
              end
          end
      end
    end
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
  PUT /interface/gre - create a GRE interface.
  RouterOS REST API uses PUT for creating resources.
  Falls back to POST /interface/gre/add on older RouterOS versions.
  """
  @spec gre_add(Auth.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def gre_add(auth, ip, attrs, opts \\ []) when is_map(attrs) or is_list(attrs) do
    case put(auth, ip, "/interface/gre", attrs, opts) do
      {:ok, _} = ok ->
        ok

      {:error, %Error{status: 400, details: det}} = err ->
        if is_binary(det) and String.contains?(det, "no such command") do
          post(auth, ip, "/interface/gre/add", attrs, opts)
        else
          err
        end

      other ->
        other
    end
  end

  @doc """
  PATCH /interface/gre/{id}
  """
  @spec gre_update(Auth.t(), String.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def gre_update(auth, ip, id, attrs, opts \\ []) when is_binary(id) do
    patch(auth, ip, "/interface/gre/#{id}", attrs, opts)
  end

  @doc """
  DELETE /interface/gre/{id}
  """
  @spec gre_delete(Auth.t(), String.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def gre_delete(auth, ip, id, opts \\ []) when is_binary(id) do
    delete(auth, ip, "/interface/gre/#{id}", opts)
  end

  @doc """
  Ensure a GRE interface by name or .id. If present, patches only differing keys.
  Returns {:ok, %{id: id | name, name: name, changed: [keys]}}.
  """
  @spec gre_ensure(Auth.t(), String.t(), String.t(), map(), Keyword.t()) ::
          {:ok, %{id: String.t(), name: String.t(), changed: [String.t()]}} | {:error, term()}
  def gre_ensure(auth, ip, ident, attrs \\ %{}, opts \\ [])
      when is_binary(ident) and is_map(attrs) do
    with {:ok, list} <- gre_list(auth, ip, opts) do
      case Enum.find(list || [], fn e -> e[".id"] == ident or e["name"] == ident end) do
        nil ->
          merged = Map.put(attrs, "name", ident)

          case gre_add(auth, ip, merged, opts) do
            {:ok, _} ->
              {:ok, %{id: ident, name: ident, changed: Enum.map(Map.keys(merged), &to_string/1)}}

            {:error, _} = err ->
              err
          end

        %{".id" => id} = existing ->
          name = Map.get(existing, "name", ident)

          changed_map =
            attrs
            |> Enum.reduce(%{}, fn {k, v}, acc ->
              existing_v = Map.get(existing, k)
              if existing_v == v, do: acc, else: Map.put(acc, k, v)
            end)

          case Map.keys(changed_map) do
            [] ->
              {:ok, %{id: id, name: name, changed: []}}

            keys ->
              case gre_update(auth, ip, id, changed_map, opts) do
                {:ok, _} -> {:ok, %{id: id, name: name, changed: Enum.map(keys, &to_string/1)}}
                {:error, _} = err -> err
              end
          end
      end
    end
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

  # User Management

  @doc """
  GET /user
  """
  @spec user_list(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def user_list(auth, ip, opts \\ []) do
    get(auth, ip, "/user", opts)
  end

  @doc """
  PUT /user - create a new user.
  RouterOS REST API uses PUT for creating resources.
  """
  @spec user_add(Auth.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def user_add(auth, ip, attrs, opts \\ []) when is_map(attrs) or is_list(attrs) do
    put(auth, ip, "/user", attrs, opts)
  end

  @doc """
  PATCH /user/{id} - update a user by .id.
  """
  @spec user_update(Auth.t(), String.t(), String.t(), map() | list(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def user_update(auth, ip, id, attrs, opts \\ []) when is_binary(id) do
    patch(auth, ip, "/user/#{id}", attrs, opts)
  end

  @doc """
  DELETE /user/{id} - delete a user by .id.
  """
  @spec user_delete(Auth.t(), String.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def user_delete(auth, ip, id, opts \\ []) when is_binary(id) do
    delete(auth, ip, "/user/#{id}", opts)
  end

  @doc """
  GET /user/group
  """
  @spec user_group_list(Auth.t(), String.t(), Keyword.t()) ::
          {:ok, any() | nil} | {:error, Error.t()}
  def user_group_list(auth, ip, opts \\ []) do
    get(auth, ip, "/user/group", opts)
  end

  @doc """
  Ensure a user exists by name. If present, patches only differing keys.
  Returns {:ok, %{id: id | name, name: name, changed: [keys]}}.
  """
  @spec user_ensure(Auth.t(), String.t(), String.t(), map(), Keyword.t()) ::
          {:ok, %{id: String.t(), name: String.t(), changed: [String.t()]}} | {:error, term()}
  def user_ensure(auth, ip, name, attrs \\ %{}, opts \\ [])
      when is_binary(name) and is_map(attrs) do
    with {:ok, list} <- user_list(auth, ip, opts) do
      case Enum.find(list || [], fn e -> e[".id"] == name or e["name"] == name end) do
        nil ->
          merged = Map.put(attrs, "name", name)

          case user_add(auth, ip, merged, opts) do
            {:ok, _} ->
              {:ok, %{id: name, name: name, changed: Enum.map(Map.keys(merged), &to_string/1)}}

            {:error, _} = err ->
              err
          end

        %{".id" => id} = existing ->
          user_name = Map.get(existing, "name", name)

          changed_map =
            attrs
            |> Enum.reduce(%{}, fn {k, v}, acc ->
              existing_v = Map.get(existing, k)
              if existing_v == v, do: acc, else: Map.put(acc, k, v)
            end)

          case Map.keys(changed_map) do
            [] ->
              {:ok, %{id: id, name: user_name, changed: []}}

            keys ->
              case user_update(auth, ip, id, changed_map, opts) do
                {:ok, _} ->
                  {:ok, %{id: id, name: user_name, changed: Enum.map(keys, &to_string/1)}}

                {:error, _} = err ->
                  err
              end
          end
      end
    end
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
