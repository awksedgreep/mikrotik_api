# MikrotikApi Feature Requests

Feature requests identified while building RouterOS Cluster Manager.

## 1. Options Support for All Wrappers - DONE

All wrapper functions now accept and pass through `opts` for scheme/port configuration:

```elixir
# All functions support opts
def wireguard_interface_list(auth, host, opts \\ [])
```

Options supported:
- `scheme: :http | :https`
- `port: integer`

## 2. WireGuard Interface Operations - DONE

```elixir
# List interfaces
def wireguard_interface_list(auth, host, opts \\ [])
# GET /interface/wireguard

# Create interface
def wireguard_interface_add(auth, host, attrs, opts \\ [])
# POST /interface/wireguard (with fallback to /add)

# Update interface
def wireguard_interface_update(auth, host, id, attrs, opts \\ [])
# PATCH /interface/wireguard/{id}

# Delete interface
def wireguard_interface_delete(auth, host, id, opts \\ [])
# DELETE /interface/wireguard/{id}

# Ensure interface exists with desired attributes
def wireguard_interface_ensure(auth, host, ident, attrs \\ %{}, opts \\ [])
```

## 3. WireGuard Peer Operations - DONE

```elixir
# List peers
def wireguard_peer_list(auth, host, opts \\ [])
# GET /interface/wireguard/peers

# Create peer
def wireguard_peer_add(auth, host, attrs, opts \\ [])
# POST /interface/wireguard/peers (with fallback to /add)

# Update peer
def wireguard_peer_update(auth, host, id, attrs, opts \\ [])
# PATCH /interface/wireguard/peers/{id}

# Delete peer
def wireguard_peer_delete(auth, host, id, opts \\ [])
# DELETE /interface/wireguard/peers/{id}

# Ensure peer exists with desired attributes
def wireguard_peer_ensure(auth, host, interface, public_key, attrs \\ %{}, opts \\ [])
```

## 4. DNS Static Record Operations - DONE

```elixir
# List static records
def dns_static_list(auth, host, opts \\ [])
# GET /ip/dns/static

# Create record
def dns_static_add(auth, host, attrs, opts \\ [])
# PUT /ip/dns/static

# Update record
def dns_static_update(auth, host, id, attrs, opts \\ [])
# PATCH /ip/dns/static/{id}

# Delete record
def dns_static_delete(auth, host, id, opts \\ [])
# DELETE /ip/dns/static/{id}

# Ensure record exists with desired attributes
def dns_static_ensure(auth, host, name, attrs \\ %{}, opts \\ [])
```

## 5. DNS Settings Operations - DONE

```elixir
# Get DNS server settings
def dns_settings_get(auth, host, opts \\ [])
# GET /ip/dns

# Update DNS server settings
def dns_settings_set(auth, host, attrs, opts \\ [])
# POST /ip/dns/set
```

## 6. DNS Cache Operations - DONE

```elixir
# List cache entries
def dns_cache_list(auth, host, opts \\ [])
# GET /ip/dns/cache

# Flush cache
def dns_cache_flush(auth, host, opts \\ [])
# POST /ip/dns/cache/flush
```

## 7. User Management Operations - DONE

```elixir
# List users
def user_list(auth, host, opts \\ [])
# GET /user

# Create user
def user_add(auth, host, attrs, opts \\ [])
# PUT /user

# Update user
def user_update(auth, host, id, attrs, opts \\ [])
# PATCH /user/{id}

# Delete user
def user_delete(auth, host, id, opts \\ [])
# DELETE /user/{id}

# List user groups
def user_group_list(auth, host, opts \\ [])
# GET /user/group

# List active sessions
def user_active_list(auth, host, opts \\ [])
# GET /user/active

# Ensure user exists with desired attributes
def user_ensure(auth, host, name, attrs \\ %{}, opts \\ [])
```

## 8. GRE Interface Operations - DONE

```elixir
# List GRE interfaces
def gre_list(auth, host, opts \\ [])
# GET /interface/gre

# Create GRE interface
def gre_add(auth, host, attrs, opts \\ [])
# POST /interface/gre (with fallback to /add)

# Update GRE interface
def gre_update(auth, host, id, attrs, opts \\ [])
# PATCH /interface/gre/{id}

# Delete GRE interface
def gre_delete(auth, host, id, opts \\ [])
# DELETE /interface/gre/{id}

# Ensure GRE interface exists with desired attributes
def gre_ensure(auth, host, ident, attrs \\ %{}, opts \\ [])
```

## 9. System Information - DONE

```elixir
# Get system resource info (CPU, memory, uptime, version)
def system_resource(auth, host, opts \\ [])
# GET /system/resource

# Get system identity (router name)
def system_identity(auth, host, opts \\ [])
# GET /system/identity

# Set system identity (router name)
def system_identity_set(auth, host, name, opts \\ [])
# POST /system/identity/set
```

## Notes

### HTTP Methods for RouterOS REST API

| Operation | Method | Path Pattern |
|-----------|--------|--------------|
| List | GET | `/resource` |
| Create | PUT | `/resource` |
| Read one | GET | `/resource/{id}` |
| Update | PATCH | `/resource/{id}` |
| Delete | DELETE | `/resource/{id}` |
| Action | POST | `/resource/action` |

### Common Gotchas

1. **PUT for create, not POST** - RouterOS REST API uses PUT to create new resources
2. **Actions use POST** - Operations like `/user/set`, `/dns/cache/flush` use POST
3. **Port 80 for HTTP, 443 for HTTPS** - Not the traditional API ports (8728/8729) which are for the binary protocol
4. **The `.id` field** - RouterOS uses `.id` (with dot) for resource identifiers

### Implementation Notes

- All wrapper functions now accept `opts \\ []` for scheme/port configuration
- Functions include fallback paths for older RouterOS versions where needed
- Each resource type includes an `_ensure` function that creates if missing or patches if changed
- The library automatically handles JSON encoding/decoding
