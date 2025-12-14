# Changelog

All notable changes to this project will be documented in this file.

## 0.3.2 - 2025-12-14

### Added
- DNS Static Record operations: `dns_static_list/3`, `dns_static_add/4`, `dns_static_update/5`, `dns_static_delete/4`, `dns_static_ensure/5`
- DNS Settings operations: `dns_settings_get/3`, `dns_settings_set/4`
- DNS Cache flush: `dns_cache_flush/3`
- User Management operations: `user_list/3`, `user_add/4`, `user_update/5`, `user_delete/4`, `user_group_list/3`, `user_ensure/5`
- System Identity operations: `system_identity/3`, `system_identity_set/4`
- Integration test suite (`test/integration_test.exs`) for testing against real routers

### Fixed
- **BREAKING**: Changed all create operations from POST to PUT per RouterOS REST API specification
  - Affected functions: `ip_address_add`, `firewall_filter_add`, `firewall_nat_add`, `dhcp_lease_add`, `route_add`, `bridge_add`, `bridge_port_add`, `bridge_vlan_add`, `wireless_interface_add`, `wireless_security_profile_add`, `capsman_security_add`, `capsman_provisioning_add`, `wifi_ssid_add`, `wifi_security_add`, `wireguard_interface_add`, `wireguard_peer_add`, `gre_add`, `user_add`, `dns_static_add`
- Fixed `dns_cache_flush` to send empty object `{}` instead of `null`

## 0.3.0 - 2025-09-14
- Add Livebook notebooks under livebook/ with runnable examples:
  - 01_quickstart.livemd
  - 02_auth_and_tls.livemd
  - 03_crud_basics.livemd
  - 04_ensure_workflows.livemd
  - 05_multi_and_probe.livemd
- Wire notebooks into ExDoc docs (extras, groups_for_extras)
- Update README to reflect Hex availability and link to HexDocs
- Bump version to 0.3.0

## 0.2.0 - 2025-09-14
- Publish initial Hex release with HTTP/TLS via :httpc/:ssl and built-in JSON
- Add ex_doc as dev dependency and publish docs
