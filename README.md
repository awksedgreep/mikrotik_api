# MikrotikApi

An Elixir wrapper for MikroTik RouterOS REST API. Auth is established once and passed per call alongside a simple target IP (IPv4/IPv6). We bias toward programmatic usage with POST for create/command-style operations while supporting standard REST verbs.

Reference: MikroTik RouterOS REST API — https://help.mikrotik.com/docs/spaces/ROS/pages/47579162/REST+API

## Goals
- Keep the surface area small and pragmatic; don’t overcomplicate.
- Stateless by default: establish Auth once and pass it per call with a target IP; do not embed credentials in the target.
- Prefer HTTPS with proper certificate verification; allow opt-out for lab setups.
- Use Logger for all output (no IO.puts/IO.inspect), and redact credentials.

See rest_api.md for the full specification and plan.

## Installation

Add to your deps (library not yet published to Hex):

```elixir
# mix.exs (in your host application)

def deps do
  [
    # When published on Hex:
    {:mikrotik_api, "~> 0.1"}

    # For local development prior to Hex, use a path or VCS dep instead:
    # {:mikrotik_api, path: "/absolute/path/to/mikrotik_api"}
  ]
end
```

## Quick Start

Transport configuration
- Default scheme is configurable via your host app config.
- Over WireGuard, HTTP is acceptable and simpler to operate; HTTPS remains supported if you prefer certificates.

Examples:

```elixir
# config/runtime.exs (in your host application)
import Config
config :mikrotik_api, default_scheme: :http
# For HTTPS by default instead:
# config :mikrotik_api, default_scheme: :https
```

```elixir
# Establish auth once; target is just an IP
auth = MikrotikApi.Auth.new(
  username: System.get_env("MT_USER"),
  password: System.get_env("MT_PASS"),
  verify: :verify_peer
)

ip = "10.0.0.1"

# GET system resource over WireGuard (HTTP inside private network)
# If you want HTTPS, set default_scheme: :https or pass scheme: :https per call.
case MikrotikApi.get(auth, ip, "/system/resource", scheme: :http) do
  {:ok, data} -> Logger.info("system resource ok")
  {:error, err} -> Logger.error("system resource failed: #{inspect(err)}")
end

# POST to create an IP address (programmatic workflow)
attrs = %{"address" => "192.168.88.2/24", "interface" => "bridge"}
# For HTTPS with self-signed certs in lab, you can use verify: :verify_none (accepting the risk):
# auth = MikrotikApi.Auth.new(username: ..., password: ..., verify: :verify_none)
# For HTTPS with real certs, prefer verify: :verify_peer and provide CA info if needed:
# auth = MikrotikApi.Auth.new(username: ..., password: ..., verify: :verify_peer, ssl_opts: [cacertfile: '/etc/ssl/certs/ca-bundle.crt'])
case MikrotikApi.post(auth, ip, "/ip/address", attrs, scheme: :http) do
  {:ok, created} -> Logger.info("added ip address")
  {:error, err} -> Logger.error("add ip failed: #{inspect(err)}")
end
```

## Security Notes
- Prefer HTTPS (www-ssl) as advised by MikroTik; avoid HTTP except for isolated testing.
- For self-signed routers in lab environments, you may set verify: :verify_none, but understand the risks.

## API Overview

Core functions (generic verbs)
- get(auth, ip, path, opts \\ [])
- post(auth, ip, path, body \\ nil, opts \\ [])
- put(auth, ip, path, body, opts \\ [])
- patch(auth, ip, path, body, opts \\ [])
- delete(auth, ip, path, opts \\ [])

Common opts
- scheme: :http | :https (default from config :mikrotik_api, :default_scheme)
- params: map for query params
- headers: list of {binary(), binary()}
- decode: true | false (default true). When true, responses are decoded via internal JSON; false returns raw body strings.

Helper functions (selected)
- System: system_resource/2
- Interfaces: interface_list/2, interface_update/4, interface_enable/3, interface_disable/3
- IP addresses: ip_address_list/2, ip_address_add/3, ip_address_update/4, ip_address_delete/3
- DHCP leases: dhcp_lease_list/2, dhcp_lease_add/3, dhcp_lease_update/4, dhcp_lease_delete/3
- Firewall filter: firewall_filter_list/2, firewall_filter_add/3, firewall_filter_delete/3
- Routes: route_list/2, route_add/3, route_delete/3

HTTP over WireGuard (decode: true)
```elixir
auth = MikrotikApi.Auth.new(
  username: System.get_env("MT_USER"),
  password: System.get_env("MT_PASS"),
  verify: :verify_none
)

ip = System.get_env("MT_IP")

{:ok, sys} = MikrotikApi.system_resource(auth, ip, scheme: :http)
{:ok, ip_addrs} = MikrotikApi.ip_address_list(auth, ip, scheme: :http)
```

HTTPS with verify_peer and CA
```elixir
auth = MikrotikApi.Auth.new(
  username: System.get_env("MT_USER"),
  password: System.get_env("MT_PASS"),
  verify: :verify_peer,
  ssl_opts: [cacertfile: "/path/to/ca.pem"]
)

ip = System.get_env("MT_IP")

{:ok, sys} = MikrotikApi.system_resource(auth, ip, scheme: :https)
```

## Reference
- MikroTik RouterOS REST API: https://help.mikrotik.com/docs/spaces/ROS/pages/47579162/REST+API
- See rest_api.md for the complete plan and API surface.

