### Step-by-Step API Calls for Creating WireGuard Interfaces on Both Routers

To achieve this setup using the MikroTik REST API (available in RouterOS v7.9+ via HTTPS on port 443 when `www-ssl` is enabled), you'll make HTTP POST requests to the `/rest/` endpoint on each router. The REST API maps directly to RouterOS API commands like `/interface/wireguard/add` and `/interface/wireguard/getall`. 

Key notes:
- Authentication: Include Basic Auth in headers (base64-encoded `username:password`).
- Request format: POST to `https://<router-ip>/rest/interface/wireguard/...` with JSON body for parameters (e.g., `{"name": "wg-vrrp"}`).
- Keys: Leaving `private-key` unspecified (or set to `"auto"`) triggers automatic generation. The public key is derived from it.
- VRRP context: This creates identical WireGuard configs on both routers for seamless failover (e.g., same interface name, keys, and peers). Assume you add a peer for the remote endpoint separately if needed (e.g., via `/rest/interface/wireguard/peers/add`).
- Error handling: Responses include `!done` on success or `!trap` with errors.

#### 1. On the Primary Router: Create the Interface and Retrieve Keys
   - **Create the WireGuard interface** (keys generate automatically):  
     POST `https://<primary-router-ip>/rest/interface/wireguard/add`  
     Body:  
     ```json
     {
       "name": "wg-vrrp",
       "listen-port": 51820,
       "mtu": 1420,
       "private-key": "auto"
     }
     ```  
     Response: `{"ret": "!done", ".id": "*1"}` (success; `.id` is the new item's ID, e.g., `*1`).

   - **Retrieve the private and public keys** (to copy to the secondary router):  
     POST `https://<primary-router-ip>/rest/interface/wireguard/getall`  
     Body:  
     ```json
     {
       ".proplist": "name,private-key,public-key"
     }
     ```  
     (No query filter needed if there's only one; otherwise add `"?name=wg-vrrp"` under a `.query` key for specificity.)  
     Response example (excerpt):  
     ```json
     [
       {
         ".id": "*1",
         "name": "wg-vrrp",
         "private-key": "yAnz5TF+lXXJte14tji3zlMNq+hd2rYuiG44x1HoDmk=",
         "public-key": "xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg="
       }
     ]
     ```  
     Copy the `private-key` and `public-key` values.

#### 2. On the Secondary (VRRP) Router: Create the Identical Interface
   - **Create the WireGuard interface** (using the primary's private key for identical config):  
     POST `https://<secondary-router-ip>/rest/interface/wireguard/add`  
     Body:  
     ```json
     {
       "name": "wg-vrrp",
       "listen-port": 51820,
       "mtu": 1420,
       "private-key": "<paste-private-key-from-primary>"
     }
     ```  
     (The public key will auto-derive identically from the private key.)  
     Response: `{"ret": "!done", ".id": "*1"}`.

   - **Verify the keys match** (optional, for confirmation):  
     POST `https://<secondary-router-ip>/rest/interface/wireguard/getall`  
     Body:  
     ```json
     {
       ".proplist": "name,private-key,public-key"
     }
     ```  
     Response should match the primary's keys exactly.

#### Additional Steps (Common to Both Routers)
- **Assign an IP address** to the interface (e.g., for the tunnel subnet):  
  POST `https://<router-ip>/rest/ip/address/add`  
  Body:  
  ```json
  {
    "address": "10.0.0.1/30",
    "interface": "wg-vrrp"
  }
  ```
- **Add a peer** (if connecting to a remote endpoint; repeat on both routers with the remote's public key):  
  POST `https://<router-ip>/rest/interface/wireguard/peers/add`  
  Body:  
  ```json
  {
    "interface": "wg-vrrp",
    "public-key": "<remote-public-key>",
    "allowed-address": "10.0.0.2/32",
    "endpoint-address": "<remote-ip>",
    "endpoint-port": 51820,
    "persistent-keepalive": "25"
  }
  ```
- **Enable the interface** (if disabled):  
  POST `https://<router-ip>/rest/interface/set`  
  Body:  
  ```json
  {
    ".id": "*1",
    "disabled": false
  }
  ```
- Firewall: Add rules to allow UDP on the listen-port (e.g., via `/rest/ip/firewall/filter/add`).

This ensures both routers have synchronized WireGuard configs for VRRP failover. Test connectivity post-setup. For full API details, refer to the MikroTik REST API docs.
