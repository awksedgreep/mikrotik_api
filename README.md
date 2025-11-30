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

Add to your deps from Hex:

```elixir
# mix.exs (in your host application)

def deps do
  [
    {:mikrotik_api, "~> 0.3"}
  ]
end
```

- Hex package: https://hex.pm/packages/mikrotik_api
- HexDocs: https://hexdocs.pm/mikrotik_api
- Livebooks: see files under livebook/ and HexDocs “Livebooks” section

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
- Private keys: The library never logs private-key values. Some devices may not return private-key via REST after creation; in that case the pair workflow returns {:error, %MikrotikApi.Error{reason: :wireguard_private_key_unreadable}}. As a fallback, consider supplying a known private key or generating one client-side in a future step.

## API Overview

Telemetry helpers (Phase 1–4)
- System/operations
  - system_health/3 — GET /system/health
  - system_packages/3 — GET /system/package
  - firewall_connection_list/3 — GET /ip/firewall/connection
  - dns_config/3 — GET /ip/dns
  - dns_cache_list/3 — GET /ip/dns/cache
  - ip_pool_list/3 — GET /ip/pool
  - firewall_address_list/3 — GET /ip/firewall/address-list
- IPv6
  - ipv6_route_list/3 — GET /ipv6/route
  - ipv6_pool_list/3 — GET /ipv6/pool
  - ipv6_firewall_filter_list/3 — GET /ipv6/firewall/filter
  - ipv6_neighbor_list/3 — GET /ipv6/neighbor
- ipv6_firewall_address_list/3 — GET /ipv6/firewall/address-list

- Wireless/WiFi and CAPsMAN (Phase 3)
  - wireless_registration_table/3 — GET /interface/wireless/registration-table
  - wireless_interface_list/3, wireless_interface_add/4, wireless_interface_update/5, wireless_interface_delete/4, wireless_interface_ensure/5
  - wireless_security_profile_list/3, wireless_security_profile_add/4, wireless_security_profile_update/5, wireless_security_profile_delete/4, wireless_security_profile_ensure/5
  - wifi_interface_list/3, wifi_interface_update/5
  - wifi_ssid_list/3, wifi_ssid_add/4, wifi_ssid_update/5, wifi_ssid_delete/4, wifi_ssid_ensure/5
  - wifi_security_list/3, wifi_security_add/4, wifi_security_update/5, wifi_security_delete/4, wifi_security_ensure/5
  - capsman_interface_list/3, capsman_registration_table/3, capsman_security_list/3, capsman_security_add/4, capsman_security_ensure/5, capsman_provisioning_list/3, capsman_provisioning_add/4, capsman_provisioning_ensure/4

- Extended telemetry (Phase 4)
  - ethernet_poe_list/3 — GET /interface/ethernet/poe
  - interface_ethernet_monitor/4 — GET /interface/ethernet/monitor/{ident}
  - tool_netwatch_list/3 — GET /tool/netwatch
  - ip_cloud_info/3 — GET /ip/cloud
  - eoip_list/3 — GET /interface/eoip
  - gre_list/3 — GET /interface/gre; gre_add/4; gre_update/5; gre_delete/4; gre_ensure/5
  - ipip_list/3 — GET /interface/ipip
  - ethernet_switch_port_list/3 — GET /interface/ethernet/switch/port
  - user_active_list/3 — GET /user/active
  - queue_simple_list/3 — GET /queue/simple
  - queue_tree_list/3 — GET /queue/tree
  - routing_bfd_list/3 — GET /routing/bfd/session
  - routing_bgp_list/3 — GET /routing/bgp/session
  - routing_stats/3 — GET /routing/stats
  - certificate_list/3 — GET /certificate
  - container_list/3 — GET /container

- WireGuard
  - wireguard_interface_list/3 — GET /interface/wireguard
  - wireguard_interface_add/4 — POST /interface/wireguard
  - wireguard_interface_update/5 — PATCH /interface/wireguard/{id}
  - wireguard_interface_delete/4 — DELETE /interface/wireguard/{id}
  - wireguard_interface_ensure/5 — ensure by name, patch only diffs
  - ensure_wireguard_pair/7 — sequential workflow to create on router A, read private-key, and apply same private-key on router B (for VRRP HA)

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
- decode: true | false (default true). When true, responses are decoded via Elixir's built-in JSON; false returns raw body strings.

Helper functions (selected)
- Probe: probe_device/3 — summarize system info and counts for key tables (interfaces, IP addresses, ARP, neighbors)
- Probe: probe_wireless/3 — summarize availability for wireless/wifi endpoints
- Probe: probe_wireless/3 — summarize availability for wireless/wifi endpoints
- Probe: probe_device/3 — summarize system info and counts for key tables (interfaces, IP addresses, ARP, neighbors)
- System: system_resource/2
- Interfaces: interface_list/2, interface_update/4, interface_enable/3, interface_disable/3, interface_ensure/5
- IP addresses: ip_address_list/2, ip_address_add/3, ip_address_update/4, ip_address_delete/3, ip_address_ensure/4
- DHCP leases: dhcp_lease_list/2, dhcp_lease_add/3, dhcp_lease_update/4, dhcp_lease_delete/3, dhcp_lease_ensure/4
- Firewall filter: firewall_filter_list/2, firewall_filter_add/3, firewall_filter_delete/3, firewall_filter_ensure/4
- Firewall NAT: firewall_nat_list/2, firewall_nat_add/3, firewall_nat_delete/3, firewall_nat_ensure/4
- Routes: route_list/2, route_add/3, route_delete/3, route_ensure/4
- Bridges: bridge_list/2, bridge_add/3, bridge_update/4, bridge_delete/3, bridge_ensure/5
- Bridge ports: bridge_port_list/2, bridge_port_add/3, bridge_port_update/4, bridge_port_delete/3
- Bridge VLANs: bridge_vlan_list/2, bridge_vlan_add/3, bridge_vlan_update/4, bridge_vlan_delete/3, bridge_vlan_ensure/6
- Wireless (legacy): wireless_interface_list/2, wireless_interface_add/3, wireless_interface_update/4, wireless_interface_delete/3, wireless_interface_ensure/5, wireless_registration_table/2, wireless_security_profile_list/2, wireless_security_profile_add/3, wireless_security_profile_update/4, wireless_security_profile_delete/3, wireless_security_profile_ensure/5
- WiFi (wifiwave2): wifi_interface_list/2, wifi_interface_update/4, wifi_ssid_list/2, wifi_ssid_add/3, wifi_ssid_update/4, wifi_ssid_delete/3, wifi_security_list/2, wifi_security_add/3, wifi_security_update/4, wifi_security_delete/3, wifi_security_ensure/5, wifi_ssid_ensure/5

HTTP over WireGuard (decode: true)

ARP and neighbors
```elixir
auth = MikrotikApi.Auth.new(username: System.get_env("MT_USER"), password: System.get_env("MT_PASS"), verify: :verify_none)
ip = System.get_env("MT_IP")
{:ok, arp} = MikrotikApi.arp_list(auth, ip, scheme: :http)
{:ok, neighbors} = MikrotikApi.neighbor_list(auth, ip, scheme: :http)
```
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

WiFi notes
- Ensure helpers are provided to idempotently create or reuse entries:
  - wifi_security_ensure/5 (name, attrs)
  - wifi_ssid_ensure/5 (name, attrs)

CAPsMAN examples
- Ensure helpers are provided:
  - capsman_security_ensure/5
  - capsman_provisioning_ensure/4
```elixir
auth = MikrotikApi.Auth.new(username: System.get_env("MT_USER"), password: System.get_env("MT_PASS"), verify: :verify_none)
ip = System.get_env("MT_IP")
{:ok, caps_if} = MikrotikApi.capsman_interface_list(auth, ip, scheme: :http)
{:ok, caps_sec} = MikrotikApi.capsman_security_list(auth, ip, scheme: :http)
{:ok, caps_reg} = MikrotikApi.capsman_registration_table(auth, ip, scheme: :http)
```

- Some wifiwave2 subresources (e.g., /interface/wifi/ssid) may return 500 on devices without WiFi configured or when the package/version doesn’t expose SSIDs yet. The library will return {:error, %MikrotikApi.Error{reason: :wifi_ssid_unavailable}} in this case.
- Ensure helpers are provided to idempotently create or reuse entries:
  - wifi_security_ensure/5 (name, attrs)
  - wifi_ssid_ensure/5 (name, attrs)
- Some wifiwave2 subresources (e.g., /interface/wifi/ssid) may return 500 on devices without WiFi configured or when the package/version doesn’t expose SSIDs yet. The library will return {:error, %MikrotikApi.Error{reason: :wifi_ssid_unavailable}} in this case.
- Some wifiwave2 subresources (e.g., /interface/wifi/ssid) may return 500 on devices without WiFi configured or when the package/version doesn’t expose SSIDs yet. The library will return {:error, %MikrotikApi.Error{reason: :wifi_ssid_unavailable}} in this case.

Probe examples
```elixir
auth = MikrotikApi.Auth.new(
  username: System.get_env("MT_USER"),
  password: System.get_env("MT_PASS"),
  verify: :verify_none
)

ip = System.get_env("MT_IP")
{:ok, summary} = MikrotikApi.probe_wireless(auth, ip, scheme: :http)
# summary => %{wireless: %{...}, wifi: %{...}}
```

```elixir
auth = MikrotikApi.Auth.new(
  username: System.get_env("MT_USER"),
  password: System.get_env("MT_PASS"),
  verify: :verify_none
)

ip = System.get_env("MT_IP")
{:ok, summary} = MikrotikApi.probe_device(auth, ip, scheme: :http)
# summary => %{system: {:ok, %{...}}, counts: %{interfaces: n, ip_addresses: n, arp: n, neighbors: n}}

## Batch reads (multi)
To fetch the same path across multiple devices concurrently, use multi/6.

Example:
```elixir
auth = MikrotikApi.Auth.new(username: System.get_env("MT_USER"), password: System.get_env("MT_PASS"), verify: :verify_none)
ips = ["192.168.88.1", "192.168.88.2"]
results = MikrotikApi.multi(auth, ips, :get, "/system/resource", [scheme: :http], max_concurrency: 5, timeout: 10_000)
# [%{ip: "192.168.88.1", result: {:ok, %{...}}}, ...]
```

## Developer guardrails
To prevent regressions, run:

```bash
mix guardrails
```
This task scans for disallowed patterns (IO.puts/IO.inspect and the legacy MikrotikApi.JSON).

## Normalization helpers (optional)
The library includes optional utilities for exporters to normalize string fields commonly found in RouterOS responses.

Examples:
```elixir
# Normalize wireless registration-table entries (legacy wireless)
{:ok, regs} = MikrotikApi.wireless_registration_table(auth, ip, scheme: :http)
normalized =
  Enum.map(regs, fn e ->
    e
    |> Map.update("rx-signal", nil, &MikrotikApi.Normalize.to_int/1)
    |> Map.update("tx-rate", nil, &MikrotikApi.Normalize.parse_rate_mbps/1)
    |> Map.update("rx-rate", nil, &MikrotikApi.Normalize.parse_rate_mbps/1)
  end)

# Normalize booleans
val = MikrotikApi.Normalize.normalize_bool("enabled") # => true
```
```

Multi (concurrent) examples
```elixir
auth = MikrotikApi.Auth.new(username: System.get_env("MT_USER"), password: System.get_env("MT_PASS"), verify: :verify_none)
ips = ["192.168.88.1", "192.168.88.2", "192.168.88.3"]
results = MikrotikApi.multi(auth, ips, :get, "/system/resource", [scheme: :http], max_concurrency: 5, timeout: 10_000)
# results => [%{ip: "192.168.88.1", result: {:ok, %{...}}}, ...]
```

Ensure examples
```elixir
# Route ensure
attrs = %{"dst-address" => "10.10.0.0/16", "gateway" => "192.168.88.1"}
{:ok, %{dst: _, gw: _}} = MikrotikApi.route_ensure(auth, ip, attrs, scheme: :http)

# Bridge and ports/VLANs ensure
{:ok, "bridgeLocal"} = MikrotikApi.bridge_ensure(auth, ip, "bridgeLocal", %{}, scheme: :http)
{:ok, {"bridgeLocal", "ether2"}} = MikrotikApi.bridge_port_ensure(auth, ip, "bridgeLocal", "ether2", %{}, scheme: :http)
{:ok, {"bridgeLocal", "10"}} = MikrotikApi.bridge_vlan_ensure(auth, ip, "bridgeLocal", "10", %{"tagged" => "sfp-sfpplus1", "untagged" => "ether2"}, scheme: :http)

# Interface ensure (patch only changed keys)
{:ok, %{changed: _}} = MikrotikApi.interface_ensure(auth, ip, "ether1", %{"mtu" => "1500", "disabled" => "false"}, scheme: :http)

# IP address ensure
{:ok, _addr} = MikrotikApi.ip_address_ensure(auth, ip, %{"address" => "192.168.88.2/24", "interface" => "bridgeLocal"}, scheme: :http)

# DHCP lease ensure
{:ok, _lease} = MikrotikApi.dhcp_lease_ensure(auth, ip, %{"address" => "192.168.88.100", "mac-address" => "AA:BB:CC:DD:EE:FF"}, scheme: :http)

# Firewall filter ensure
rule = %{"chain" => "forward", "action" => "accept", "comment" => "allow"}
{:ok, _} = MikrotikApi.firewall_filter_ensure(auth, ip, rule, scheme: :http)

# Firewall NAT ensure (default match by chain+action)
nat_rule = %{"chain" => "dstnat", "action" => "dst-nat", "to-addresses" => "192.168.88.2"}
{:ok, _} = MikrotikApi.firewall_nat_ensure(auth, ip, nat_rule, scheme: :http)
```

WireGuard ensure and pair workflow
```elixir
# Ensure a WireGuard interface by name on a single router
{:ok, %{name: "wgA"}} = MikrotikApi.wireguard_interface_ensure(
  auth,
  ip_a,
  "wgA",
  %{"listen-port" => "51820"},
  scheme: :http
)

# Create a pair in a VRRP cluster: create on A, read private-key, apply same key on B
case MikrotikApi.ensure_wireguard_pair(
       auth,
       ip_a,
       "wgA",
       ip_b,
       "wgB",
       %{"listen-port" => "51820"},
       scheme: :http
     ) do
  {:ok, %{a: _res_a, b: _res_b}} -> Logger.info("wireguard pair ensured")
  {:error, %MikrotikApi.Error{reason: :wireguard_private_key_unreadable}} ->
    Logger.warn("RouterOS REST did not return private-key; provide or generate one as a fallback")
  other -> Logger.error("pair setup failed: #{inspect(other)}")
end
```

WiFi ensure workflow (wifiwave2)
```elixir
# Ensure a wifi security profile, then ensure an SSID using it
{:ok, _} = MikrotikApi.wifi_security_ensure(auth, ip, "SEC-PSK", %{"wpa2-pre-shared-key" => "supersecret"}, scheme: :http)
case MikrotikApi.wifi_ssid_ensure(auth, ip, "WG-LAB", %{"security" => "SEC-PSK"}, scheme: :http) do
  {:ok, _} -> :ok
  {:error, %MikrotikApi.Error{reason: :wifi_ssid_unavailable}} -> :ok # device may not expose SSIDs
  other -> other
end

# Optionally update a wifi interface to reference a configuration (if used in your setup)
# MikrotikApi.wifi_interface_update(auth, ip, "wifi1", %{"disabled" => "false"}, scheme: :http)
```

Legacy wireless ensure (wireless package)
```elixir
{:ok, _} = MikrotikApi.wireless_security_profile_ensure(auth, ip, "LEGACY-SEC", %{"mode" => "dynamic-keys"}, scheme: :http)
{:ok, _} = MikrotikApi.wireless_interface_ensure(auth, ip, "wlan1", %{"disabled" => "false"}, scheme: :http)
```

CAPsMAN ensure examples
```elixir
{:ok, _} = MikrotikApi.capsman_security_ensure(auth, ip, "CAPS-SEC", %{"authentication-types" => "wpa2-psk"}, scheme: :http)
{:ok, _} = MikrotikApi.capsman_provisioning_ensure(auth, ip, %{"action" => "create-enabled", "master-configuration" => "MASTER"}, scheme: :http)
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

