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

```elixir
# Establish auth once; target is just an IP
auth = MikrotikApi.Auth.new(
  username: System.get_env("MT_USER"),
  password: System.get_env("MT_PASS"),
  verify: :verify_peer
)

ip = "10.0.0.1"

# GET system resource
case MikrotikApi.get(auth, ip, "/system/resource") do
  {:ok, data} -> Logger.info("system resource ok")
  {:error, err} -> Logger.error("system resource failed: #{inspect(err)}")
end

# POST to create an IP address (programmatic workflow)
attrs = %{"address" => "192.168.88.2/24", "interface" => "bridge"}
case MikrotikApi.post(auth, ip, "/ip/address", attrs) do
  {:ok, created} -> Logger.info("added ip address")
  {:error, err} -> Logger.error("add ip failed: #{inspect(err)}")
end
```

## Security Notes
- Prefer HTTPS (www-ssl) as advised by MikroTik; avoid HTTP except for isolated testing.
- For self-signed routers in lab environments, you may set verify: :verify_none, but understand the risks.

## Reference
- MikroTik RouterOS REST API: https://help.mikrotik.com/docs/spaces/ROS/pages/47579162/REST+API
- See rest_api.md for the complete plan and API surface.

