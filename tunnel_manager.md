# Tunnel Manager - Requirements Document

## Overview

A Phoenix web application for managing WireGuard and GRE tunnels across a MikroTik CHR (Cloud Hosted Router) cluster. The application provides both a web UI and REST API for tunnel lifecycle management.

---

## Quick Start

```bash
# Create the Phoenix project with SQLite and LiveView
mix phx.new tunnel_manager --database sqlite3 --live

# Then add dependencies to mix.exs:
# {:mikrotik_api, path: "../mikrotik_api"}  # or from hex
# {:cloak_ecto, "~> 1.3"}
# {:oban, "~> 2.17"}
# {:open_api_spex, "~> 3.18"}
```

---

## 1. Functional Requirements

### 1.1 Cluster Management

| ID | Requirement |
|----|-------------|
| CM-01 | System shall maintain a list of CHR nodes (IP, name, credentials reference) |
| CM-02 | System shall support adding/removing CHR nodes from the cluster |
| CM-03 | System shall poll cluster nodes for health status on a configurable interval |
| CM-04 | System shall display node online/offline status in the UI |

### 1.2 WireGuard Tunnel Management

| ID | Requirement |
|----|-------------|
| WG-01 | System shall list all WireGuard interfaces across the cluster |
| WG-02 | System shall display interface details: name, listen-port, public-key, MTU, disabled status |
| WG-03 | System shall create WireGuard interfaces on a single node or replicated across cluster (using `wireguard_cluster_add`) |
| WG-04 | System shall update WireGuard interface attributes |
| WG-05 | System shall delete WireGuard interfaces (single node or cluster-wide) |
| WG-06 | System shall list WireGuard peers per interface |
| WG-07 | System shall add/update/remove peers (using `wireguard_cluster_add_peers` for cluster-wide) |
| WG-08 | System shall display peer details: public-key, endpoint, allowed-address, last-handshake, rx/tx bytes |

### 1.3 GRE Tunnel Management

| ID | Requirement |
|----|-------------|
| GRE-01 | System shall list all GRE interfaces across the cluster |
| GRE-02 | System shall display interface details: name, local-address, remote-address, MTU, disabled status |
| GRE-03 | System shall create GRE interfaces on single node or cluster-wide |
| GRE-04 | System shall update GRE interface attributes |
| GRE-05 | System shall delete GRE interfaces (single node or cluster-wide) |
| GRE-06 | System shall support IPsec-encrypted GRE tunnels (ipsec-secret attribute) |

### 1.4 IP Address Management

| ID | Requirement |
|----|-------------|
| IP-01 | System shall assign IP addresses to tunnel interfaces |
| IP-02 | System shall display assigned addresses per interface |
| IP-03 | System shall remove IP addresses from interfaces |

### 1.5 Web Dashboard

| ID | Requirement |
|----|-------------|
| UI-01 | Dashboard shall show cluster health overview (nodes up/down) |
| UI-02 | Dashboard shall show tunnel count summary (WireGuard/GRE per node) |
| UI-03 | Dashboard shall show recent tunnel activity/changes |
| UI-04 | UI shall provide tunnel listing with search/filter capability |
| UI-05 | UI shall provide forms for creating/editing tunnels |
| UI-06 | UI shall show real-time tunnel status via LiveView |
| UI-07 | UI shall display errors and operation results clearly |
| UI-08 | UI shall support dark mode with automatic browser preference detection (`prefers-color-scheme`) |

### 1.6 REST API

| ID | Requirement |
|----|-------------|
| API-01 | API shall expose endpoints under `/api/v1` |
| API-02 | API shall support JSON request/response format |
| API-03 | API shall require authentication (API key or Bearer token) |
| API-04 | API shall return appropriate HTTP status codes |
| API-05 | API shall provide OpenAPI/Swagger documentation |

#### API Endpoints

```
# Cluster
GET    /api/v1/cluster/nodes           - List all CHR nodes
POST   /api/v1/cluster/nodes           - Add a CHR node
GET    /api/v1/cluster/nodes/:id       - Get node details
DELETE /api/v1/cluster/nodes/:id       - Remove a CHR node
GET    /api/v1/cluster/health          - Cluster health summary

# WireGuard Interfaces
GET    /api/v1/wireguard               - List all WG interfaces (cluster-wide)
POST   /api/v1/wireguard               - Create WG interface
GET    /api/v1/wireguard/:name         - Get WG interface details
PATCH  /api/v1/wireguard/:name         - Update WG interface
DELETE /api/v1/wireguard/:name         - Delete WG interface

# WireGuard Peers
GET    /api/v1/wireguard/:name/peers   - List peers for interface
POST   /api/v1/wireguard/:name/peers   - Add peer(s) to interface
DELETE /api/v1/wireguard/:name/peers/:public_key - Remove peer

# GRE Interfaces
GET    /api/v1/gre                     - List all GRE interfaces
POST   /api/v1/gre                     - Create GRE interface
GET    /api/v1/gre/:name               - Get GRE interface details
PATCH  /api/v1/gre/:name               - Update GRE interface
DELETE /api/v1/gre/:name               - Delete GRE interface

# IP Addresses
GET    /api/v1/addresses               - List all tunnel IP addresses
POST   /api/v1/addresses               - Assign IP to interface
DELETE /api/v1/addresses/:id           - Remove IP address
```

---

## 2. Non-Functional Requirements

### 2.1 Performance

| ID | Requirement |
|----|-------------|
| NF-01 | API responses shall complete within 5 seconds for single-node operations |
| NF-02 | Cluster-wide operations shall complete within 30 seconds |
| NF-03 | Dashboard shall refresh status every 30 seconds (configurable) |
| NF-04 | System shall handle clusters of up to 20 CHR nodes |

### 2.2 Security

| ID | Requirement |
|----|-------------|
| SEC-01 | MikroTik credentials shall be stored encrypted at rest |
| SEC-02 | Private keys shall never be logged or exposed via API |
| SEC-03 | Web UI shall require user authentication |
| SEC-04 | API shall require authentication token |
| SEC-05 | All MikroTik communication shall use HTTPS/TLS |
| SEC-06 | System shall support TLS certificate verification for CHR connections |

### 2.3 Reliability

| ID | Requirement |
|----|-------------|
| REL-01 | System shall gracefully handle unreachable CHR nodes |
| REL-02 | System shall retry failed operations with exponential backoff |
| REL-03 | System shall maintain audit log of all tunnel changes |

---

## 3. Data Model

### 3.1 SQLite Tables

```
nodes
├── id (integer, PK)
├── name (string, unique)
├── ip_address (string)
├── port (integer, default 443)
├── username_encrypted (binary)
├── password_encrypted (binary)
├── tls_verify (boolean, default true)
├── is_active (boolean, default true)
├── last_seen_at (utc_datetime)
├── inserted_at (utc_datetime)
└── updated_at (utc_datetime)

api_keys
├── id (integer, PK)
├── name (string)
├── key_hash (string)
├── last_used_at (utc_datetime)
├── expires_at (utc_datetime, nullable)
├── inserted_at (utc_datetime)
└── updated_at (utc_datetime)

users
├── id (integer, PK)
├── email (string, unique)
├── password_hash (string)
├── role (string: admin, operator, viewer)
├── inserted_at (utc_datetime)
└── updated_at (utc_datetime)

audit_logs
├── id (integer, PK)
├── user_id (integer, FK, nullable)
├── api_key_id (integer, FK, nullable)
├── action (string)
├── resource_type (string: wireguard, gre, node)
├── resource_name (string)
├── target_nodes (string, JSON array)
├── details (text, JSON)
├── inserted_at (utc_datetime)
└── (no updated_at - immutable)

tunnel_snapshots (optional - cached state)
├── id (integer, PK)
├── node_id (integer, FK)
├── tunnel_type (string: wireguard, gre)
├── name (string)
├── config (text, JSON)
├── fetched_at (utc_datetime)
└── (composite unique: node_id, tunnel_type, name)
```

---

## 4. Technology Stack

| Component | Technology |
|-----------|------------|
| Framework | Phoenix 1.7+ (LiveView) |
| Database | SQLite via Ecto + `ecto_sqlite3` |
| MikroTik Client | `mikrotik_api` library |
| Auth (Web) | `mix phx.gen.auth` |
| Auth (API) | Bearer token / API key |
| Encryption | `cloak_ecto` for credential encryption |
| Background Jobs | `Oban` (SQLite-compatible) |
| API Docs | `open_api_spex` |
| CSS | Tailwind (included with Phoenix) |
| Dark Mode | CSS `prefers-color-scheme` + Tailwind dark variant |

---

## 5. Configuration

```elixir
# config/runtime.exs
config :tunnel_manager,
  # Cluster polling interval (ms)
  health_check_interval: 30_000,
  
  # MikroTik connection defaults
  mikrotik_scheme: :https,
  mikrotik_timeout: 15_000,
  mikrotik_tls_verify: true,
  
  # Encryption key for credentials (from env)
  credential_encryption_key: System.get_env("CREDENTIAL_KEY")
```

---

## 6. User Roles & Permissions

| Role | Nodes | View Tunnels | Manage Tunnels | Audit Logs |
|------|-------|--------------|----------------|------------|
| Viewer | Read | Read | - | - |
| Operator | Read | Read | Create/Update/Delete | Read own |
| Admin | Full | Full | Full | Full |

---

## 7. Implementation Phases

### Phase 1: Project Foundation
- [ ] Create Phoenix project with `mix phx.new tunnel_manager --database sqlite3 --live`
- [ ] Add dependencies (`mikrotik_api`, `cloak_ecto`, `oban`, `open_api_spex`)
- [ ] Configure SQLite database
- [ ] Set up Cloak encryption vault for credentials
- [ ] Generate user authentication with `mix phx.gen.auth`
- [ ] Add role field to users
- [ ] Configure Tailwind dark mode (`darkMode: 'class'` or `'media'`)
- [ ] Create base layout with dark mode toggle and system preference detection

### Phase 2: Cluster Node Management
- [ ] Create `nodes` schema and migration
- [ ] Build Node context (CRUD operations)
- [ ] Create LiveView for node management (list, add, edit, delete)
- [ ] Implement credential encryption/decryption
- [ ] Add node connection test functionality
- [ ] Build health check GenServer (periodic polling)
- [ ] Display node status in UI (online/offline badge)

### Phase 3: WireGuard Interface Management
- [ ] Create `tunnel_snapshots` schema (optional caching)
- [ ] Build WireGuard context wrapping `mikrotik_api` calls
- [ ] Create LiveView for WireGuard interface listing
- [ ] Implement interface details view (with peers)
- [ ] Build create interface form (single node vs cluster-wide)
- [ ] Build edit interface form
- [ ] Implement delete with confirmation
- [ ] Add real-time status refresh

### Phase 4: WireGuard Peer Management
- [ ] Create peer listing component
- [ ] Build add peer form
- [ ] Implement peer deletion
- [ ] Support cluster-wide peer operations
- [ ] Display peer statistics (handshake, rx/tx)

### Phase 5: GRE Tunnel Management
- [ ] Build GRE context wrapping `mikrotik_api` calls
- [ ] Create LiveView for GRE interface listing
- [ ] Build create/edit GRE forms
- [ ] Support IPsec secret configuration
- [ ] Implement delete with confirmation

### Phase 6: IP Address Management
- [ ] Build IP address context
- [ ] Create UI for viewing addresses per interface
- [ ] Implement assign/remove IP functionality
- [ ] Link addresses to tunnel views

### Phase 7: REST API - Core
- [ ] Set up API router and pipeline
- [ ] Create `api_keys` schema and migration
- [ ] Implement API key authentication plug
- [ ] Build cluster nodes API controller
- [ ] Build WireGuard API controller
- [ ] Build GRE API controller
- [ ] Build addresses API controller
- [ ] Add consistent error response formatting

### Phase 8: REST API - Documentation
- [ ] Configure OpenAPI spec with `open_api_spex`
- [ ] Add operation specs to all API controllers
- [ ] Generate Swagger UI endpoint
- [ ] Write API usage examples in docs

### Phase 9: Audit Logging
- [ ] Create `audit_logs` schema and migration
- [ ] Build audit logging module
- [ ] Instrument all tunnel operations (create/update/delete)
- [ ] Create audit log viewer (admin only)
- [ ] Add filtering by user, resource, date range

### Phase 10: Background Jobs & Reliability
- [ ] Configure Oban with SQLite
- [ ] Create health check worker (scheduled)
- [ ] Implement retry logic for failed operations
- [ ] Add job for stale snapshot cleanup
- [ ] Create node unreachable notifications

### Phase 11: Dashboard & Polish
- [ ] Build main dashboard with cluster overview
- [ ] Add tunnel count widgets
- [ ] Show recent activity feed
- [ ] Implement search/filter across tunnels
- [ ] Add keyboard shortcuts
- [ ] Performance optimization (query tuning, caching)
- [ ] Mobile-responsive layout adjustments

### Phase 12: Testing & Documentation
- [ ] Write unit tests for contexts
- [ ] Write integration tests for LiveViews
- [ ] Write API controller tests
- [ ] Create user documentation
- [ ] Write deployment guide
- [ ] Add example systemd service file

---

## 8. Acceptance Criteria

1. **Cluster Setup**: Admin can add 3+ CHR nodes and see their health status
2. **WireGuard Lifecycle**: Operator can create a WireGuard tunnel replicated to all nodes, add peers, and delete it
3. **GRE Lifecycle**: Operator can create a GRE tunnel on a single node and delete it
4. **API Access**: External system can create/list/delete tunnels via REST API with valid API key
5. **Audit Trail**: All tunnel modifications are recorded with timestamp, user, and details
6. **Security**: Credentials are encrypted; private keys never appear in logs or API responses
7. **Dark Mode**: UI respects browser `prefers-color-scheme` and allows manual toggle

---

## 9. Future Considerations (Out of Scope v1)

- VRRP address tracking and automatic failover coordination
- Tunnel traffic graphs/metrics (RRD or time-series)
- Configuration backup/restore
- Multi-tenant support
- Webhook notifications for tunnel state changes
- IPsec policy management
- Route management tied to tunnels
- BGP session monitoring for tunnels
