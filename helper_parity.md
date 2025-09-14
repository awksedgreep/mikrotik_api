# Helper Parity Plan — Toward MKTXP-equivalent Telemetry Coverage

Context
- Project rules: use built-in JSON, OTP httpc/:ssl transport, Logger for all logs (no IO.puts/IO.inspect).
- Return shape: {:ok, data} | {:error, %MikrotikApi.Error{status, reason, details}}
- Scope: Provide thin, typed helpers over RouterOS REST endpoints to facilitate metric collection similar to MKTXP. Do not embed Prometheus formatting in this library.

Guiding principles
- Small, composable helpers that map 1:1 to RouterOS REST endpoints.
- Keep read vs write distinct. Most metrics are read-only GETs.
- Consistent naming: <domain>_<resource>_<action> where action is list|get|ensure|add|update|delete.
- Maintain existing patterns: list returns list; targeted get returns map or nil.
- Performance: support batch calls using MikrotikApi.multi/6 where it helps exporters.

Phased roadmap

Phase 1 — Operations essentials (highest exporter value)
Goal: Add helpers that unlock core operational telemetry commonly scraped by MKTXP.

Endpoints and helpers
- System health and packages
  - GET /system/health → system_health/3
  - GET /system/package → system_packages/3
- Connections
  - GET /ip/firewall/connection → firewall_connection_list/3
  - (optional follow-up) GET /ip/firewall/connection/stats if exposed → firewall_connection_stats/3
- DNS
  - GET /ip/dns → dns_config/3 (for high-level stats if provided)
  - GET /ip/dns/cache → dns_cache_list/3 (if exposed by REST)
- Pools and address lists (IPv4)
  - GET /ip/pool → ip_pool_list/3
  - GET /ip/firewall/address-list → firewall_address_list/3

Return shape examples
- system_health/3 → {:ok, map() | [map()]} depending on ROS version
- system_packages/3 → {:ok, [map()]}
- firewall_connection_list/3 → {:ok, [map()]}
- dns_config/3 → {:ok, map()} | {:ok, [map()]} depending on ROS data
- dns_cache_list/3 → {:ok, [map()]}
- ip_pool_list/3 → {:ok, [map()]}
- firewall_address_list/3 → {:ok, [map()]}

Acceptance criteria
- New helpers added with @specs, moduledocs, and tests using Transport.Mock.
- Probe device doc extended with a short example for system_health.
- No changes to public error model.

Phase 2 — IPv6 parity
Goal: Mirror IPv4 fundamentals for IPv6 to enable dual-stack telemetry.

Endpoints and helpers
- Routes and pool
  - GET /ipv6/route → ipv6_route_list/3
  - GET /ipv6/pool → ipv6_pool_list/3
- Firewall and neighbor
  - GET /ipv6/firewall/filter → ipv6_firewall_filter_list/3
  - GET /ipv6/neighbor → ipv6_neighbor_list/3
- Address lists
  - GET /ipv6/firewall/address-list → ipv6_firewall_address_list/3

Acceptance criteria
- All new helpers tested with representative payloads.
- README “API Overview” extended with IPv6 helper list.

Phase 3 — Wireless/WiFi depth and CAPsMAN clients
Goal: Expand client/registration coverage to match MKTXP’s WLAN and CAPsMAN client telemetry surface.

Endpoints and helpers
- Wireless (legacy)
  - GET /interface/wireless/registration-table → wireless_registration_table/3 (already present)
  - Ensure we expose fields commonly used by exporters (rx/tx rates, signal). Add normalization helpers if needed.
- WiFi (wifiwave2)
  - GET /interface/wifi/ssid → wifi_ssid_list/3 (present)
  - GET /interface/wifi/security → wifi_security_list/3 (present)
  - Consider wifi_station_list/3 if station endpoints exist on target devices (varies by ROS/package).
- CAPsMAN
  - GET /caps-man/registration-table → capsman_registration_table/3 (present)
  - Verify interface/security coverage for CAPsMAN metrics.

Acceptance criteria
- Document field availability and differences across wireless vs wifiwave2 vs caps-man.
- Add normalization helpers when key fields differ by platform/package.

Phase 4 — Extended telemetry (add incrementally as needed)
Goal: Broaden metrics coverage for advanced/edge exporter dashboards.

Endpoints and helpers
- POE
  - GET /interface/ethernet/poe → ethernet_poe_list/3
- Interface monitor
  - GET /interface/ethernet/monitor → interface_ethernet_monitor/4 (id/name param + options)
- Netwatch
  - GET /tool/netwatch → tool_netwatch_list/3
- Public IP
  - GET /ip/cloud → ip_cloud_info/3 (note: some deployments disable ip/cloud)
- Tunnels and security
  - GET /interface/eoip → eoip_list/3
  - GET /interface/gre → gre_list/3
  - GET /interface/ipip → ipip_list/3
  - GET /interface/lte → lte_list/3 or lte_status/3 (device-dependent)
  - GET /ip/ipsec → ipsec_active_peers/3 (verify exact subpath under REST)
- Switches
  - GET /interface/ethernet/switch/port → ethernet_switch_port_list/3
- Kid control
  - GET /ip/kid-control/device (or similar) → kid_control_device_list/3 (verify REST path)
- Users and queues
  - GET /user/active → user_active_list/3
  - GET /queue/simple → queue_simple_list/3
  - GET /queue/tree → queue_tree_list/3
- Routing protocols
  - GET /routing/bfd/session → routing_bfd_list/3
  - GET /routing/bgp/session → routing_bgp_list/3
  - GET /routing/stats → routing_stats/3 (if exposed)
- Certificates and containers
  - GET /certificate → certificate_list/3
  - GET /container → container_list/3

Acceptance criteria
- For each domain, add tests with minimal representative payloads.
- Clearly document device/version availability for less common subsystems.

Phase 5 — Exporter alignment ergonomics (non-breaking helpers)
Goal: Provide optional thin normalization utilities that make exporters simpler without embedding Prometheus concerns.

Utilities
- Normalize common numeric fields (rx/tx rates as integers, signals as integers where RouterOS returns strings).
- Normalize booleans and enumerations to consistent forms.
- Safe access utilities for fields that may not exist depending on device/ROS.

Acceptance criteria
- Utilities live in a separate internal module (e.g., MikrotikApi.Normalize) and are used by examples/tests only; keep core helpers thin.
- Document clearly that exporters may choose to apply their own normalization.

Consistent helper patterns (samples)
- IPv4 pool
  - @spec ip_pool_list(Auth.t(), String.t(), Keyword.t()) :: {:ok, [map()]} | {:error, Error.t()}
  - def ip_pool_list(auth, ip, opts \\ []), do: get(auth, ip, "/ip/pool", opts)
- Firewall address-list
  - @spec firewall_address_list(Auth.t(), String.t(), Keyword.t()) :: {:ok, [map()]} | {:error, Error.t()}
  - def firewall_address_list(auth, ip, opts \\ []), do: get(auth, ip, "/ip/firewall/address-list", opts)
- IPv6 route
  - @spec ipv6_route_list(Auth.t(), String.t(), Keyword.t()) :: {:ok, [map()]} | {:error, Error.t()}
  - def ipv6_route_list(auth, ip, opts \\ []), do: get(auth, ip, "/ipv6/route", opts)

Testing approach
- Use Transport.Mock to return static JSON payloads and HTTP status codes.
- Cover 2xx (with data), 204/empty, 4xx/5xx mapping to %Error{}, and decode_error paths.
- Add multi/6 usage tests for batch reads across multiple IPs.

Logging and security
- Use Logger.debug to log method/path/status/duration; redact secrets.
- Respect verify: in Auth and include base ssl_opts policy as currently implemented.

Performance considerations
- For exporter scenarios, encourage callers to use multi/6 for concurrent reads.
- Where endpoints accept filtering parameters, expose them via opts.params to reduce payload sizes.

Compatibility notes
- Endpoint availability varies by ROS version and installed packages (wireless vs wifiwave2, caps-man, lte, container, etc.).
- For endpoints not present, helpers should return {:error, %Error{status: code, reason: :http_error | :unavailable, details: body}}. Consider specific reason atoms for well-known unavailability cases (we already use :wifi_ssid_unavailable for 500 on certain devices).

Risks and mitigations
- REST vs API gaps: Document any endpoints that are only available via API and not REST. If critical, consider a pluggable transport in the future; out of scope for now.
- Payload variance: Add minimal normalization where it unblocks exporter usage; otherwise, surface raw fields and document.

Deliverables checklist per phase
- New helpers in MikrotikApi module with @spec and moduledocs
- Unit tests with Transport.Mock
- README “API Overview” incremental updates
- Examples demonstrating GET usage

Out of scope (for this library)
- Prometheus exporter runtime, metric name conventions, and label schemas.
- Long-running scraping loops, concurrency pools, and retry policies beyond current Auth defaults.

Next actions (recommended)
1) Implement Phase 1 helpers (system_health, system_packages, firewall_connection_list, dns_config, dns_cache_list, ip_pool_list, firewall_address_list) + tests.
2) Extend README with a short “Telemetry helpers” section and examples.
3) Validate on at least two RouterOS versions (one with wifiwave2, one with legacy wireless).
