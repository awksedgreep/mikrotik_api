# MikroTik REST API Wrapper — Specification and Plan

This document describes a minimal, pragmatic Elixir wrapper around MikroTik RouterOS REST API. The wrapper emphasizes a stateless design where an Auth struct (credentials/TLS) is established once and passed per call alongside a target IP (IPv4/IPv6), minimal external dependencies, and clear logging via Logger (no IO.puts/IO.inspect). Transport and JSON are implemented internally.

Reference: MikroTik REST API guide — https://help.mikrotik.com/docs/spaces/ROS/pages/47579162/REST+API


## 1) Overview & Scope

- Goal: Provide a thin Elixir interface over RouterOS REST endpoints for common operational tasks (query system info, list/update IP addresses, interfaces, basic firewall rules), optimized for programmatic usage.
- Philosophy: Keep it simple, composable, and close to the HTTP layer. Prefer transparency to magic.
- Out of scope (initial): full command coverage, streaming/pagination helpers, websocket/eventing.


## 2) Design Principles

- Stateless: HTTP calls are independent; Auth is established once and passed per call alongside a target IP. Do not store credentials with the target.
- Transport/JSON: Use OTP :httpc/:ssl for HTTP/TLS; JSON encoding/decoding is implemented internally (no external JSON dependency).
- Ergonomic defaults: sensible timeouts, retry on transient network/5xx errors.
- Explicitness: simple generic verbs (get/post/put/patch/delete) + a few helper functions for frequent tasks.
- Logging: Use Logger only; redact secrets; enable debug-level request/response summaries with sizes/status codes (no bodies at info level).


## 3) Dependencies

- No external JSON dependency; JSON is handled internally.
- Transport via OTP :httpc/:ssl (add :inets and :ssl to extra_applications).

No runtime configuration required beyond standard Logger settings.


## 4) Auth Struct and Target

MikrotikApi.Auth:
- username :: String.t
- password :: String.t
- verify :: :verify_peer | :verify_none (default :verify_peer; allow :verify_none only for self-signed in non-prod)
- recv_timeout :: non_neg_integer (default 15_000 ms)
- connect_timeout :: non_neg_integer (default 5_000 ms)
- retry :: %{max_attempts: 2, backoff_ms: 250}
- default_headers :: [{binary(), binary()}]

Target:
- ip :: String.t (IPv4 or IPv6 literal)
- port :: pos_integer | nil (default 443 for HTTPS, 80 for HTTP)
- scheme is provided per call via opts (default :https)
- base_path is fixed to "/rest"

Constructor: MikrotikApi.Auth.new(opts).


## 5) Core API Functions

All functions return:
- {:ok, decoded_json} on 2xx with JSON body
- {:ok, nil} when 204/empty body
- {:error, %MikrotikApi.Error{status, reason, details}} otherwise

Generic:
- call(auth, target, method, path, opts \\ []) — method is :get | :post | :put | :patch | :delete
  - opts: body (map or list), params (map), headers (list), timeout overrides, scheme (default :https)
- get(auth, target, path, opts \\ [])
- post(auth, target, path, body \\ nil, opts \\ [])
- put(auth, target, path, body, opts \\ [])
- patch(auth, target, path, body, opts \\ [])
- delete(auth, target, path, opts \\ [])

Path is appended to "/rest"; caller supplies endpoint like "/system/resource" or "/ip/address".


## 6) Minimal Resource Helpers (initial set)

- System
  - system_resource(auth, target) => GET /system/resource
- Interfaces
  - interface_list(auth, target) => GET /interface
- IP Address
  - ip_address_list(auth, target) => GET /ip/address
  - ip_address_add(auth, target, attrs) => POST /ip/address with attrs
  - ip_address_update(auth, target, id, attrs) => PATCH /ip/address/{id}
  - ip_address_delete(auth, target, id) => DELETE /ip/address/{id}
- Firewall (filter)
  - firewall_filter_list(auth, target) => GET /ip/firewall/filter
  - firewall_filter_add(auth, target, rule) => POST /ip/firewall/filter
  - firewall_filter_delete(auth, target, id) => DELETE /ip/firewall/filter/{id}

Note: IDs provided by RouterOS are often in ".id" fields; helpers accept either the string id or a resource map with ".id".


## 7) Error Handling Model

- Define %MikrotikApi.Error{status :: integer | nil, reason :: atom | String.t, details :: term()}
- Map JSON decode failures and transport errors into reason fields (:decode_error, :transport_error).
- Include response body text (truncated) in details for easier debugging.


## 8) Logging Policy

- Logger.debug: request method/path, status, duration, body size (if known), retry info.
- Logger.info: high-level action summaries (e.g., "Added IP address on host"), but avoid logging request/response bodies.
- Logger.warn/error: non-2xx responses and exceptions (with redaction).
- Redact credentials and cookies in all logs.


## 9) TLS & Security Considerations

- Prefer HTTPS (www-ssl) per MikroTik guidance. Avoid HTTP except for isolated testing.
- Support self-signed certs with verify: :verify_none only for development/testing. Document risks prominently.
- Provide timeouts and retry defaults safe for network hiccups.

Reference (MikroTik docs):
- HTTPS endpoint: https://<router_ip>/rest
- HTTP endpoint: http://<router_ip>/rest (not recommended except for testing)


## 10) Usage Examples

- Initialize auth and target

```elixir path=null start=null
auth = MikrotikApi.Auth.new(
  username: "<redacted>",
  password: "<redacted>",
  verify: :verify_peer
)

target_ip = "10.0.0.1" # IPv4 or IPv6 literal
```

- Fetch system resource info

```elixir path=null start=null
case MikrotikApi.get(auth, target_ip, "/system/resource") do
  {:ok, data} -> Logger.info("system resource ok: status=ok")
  {:error, err} -> Logger.error("system resource failed: #{inspect(err)}")
end
```

- Add an IP address (POST-centric workflow)

```elixir path=null start=null
attrs = %{"address" => "192.168.88.2/24", "interface" => "bridge"}
case MikrotikApi.post(auth, target_ip, "/ip/address", attrs) do
  {:ok, created} -> Logger.info("added ip address")
  {:error, err} -> Logger.error("add ip failed: #{inspect(err)}")
end
```

- Update (PATCH) and Delete

```elixir path=null start=null
{:ok, list} = MikrotikApi.get(auth, target_ip, "/ip/address")
[id | _] = Enum.map(list, & &1[".id"]) # example only
:ok = case MikrotikApi.patch(auth, target_ip, "/ip/address/#{id}", %{"disabled" => "no"}) do
  {:ok, _} -> Logger.info("updated ip")
  {:error, err} -> Logger.error("update failed: #{inspect(err)}")
end
:ok = case MikrotikApi.delete(auth, target_ip, "/ip/address/#{id}") do
  {:ok, _} -> Logger.info("deleted ip")
  {:error, err} -> Logger.error("delete failed: #{inspect(err)}")
end
```

Note: Examples use Logger per project rule. Replace <redacted> with secrets managed via env vars or a secrets manager.


## 11) Testing Approach

- ExUnit with Bypass to simulate RouterOS endpoints and responses (2xx, 4xx, 5xx, timeouts).
- Unit test the Client construction, header building, error mapping, and helper functions.


## 12) Roadmap

- Optional login session (POST /rest/login) and cookie reuse across calls.
- More helper modules (DHCP leases, bridges, routes, wireless, etc.).
- Structured pagination and filtering helpers.
- Typed schemas for common resources.


## 13) References

- MikroTik RouterOS REST API: https://help.mikrotik.com/docs/spaces/ROS/pages/47579162/REST+API
