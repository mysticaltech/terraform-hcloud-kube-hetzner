# Private Network Egress & Hetzner DHCP (Aug 2025)

On **August 11, 2025**, Hetzner Cloud removed the legacy DHCP *Router option (code 3)* on private networks and now relies solely on *Classless Static Route (option 121)*. Any node that forwards outbound traffic through a NAT or VPN gateway on the private network must therefore install and persist a default route to the virtual gateway (typically the first IP of the prefix, e.g. `10.0.0.1`).

Starting with this module version:

- All nodes that attach to the Hetzner private network detect the relevant interface dynamically (no hardcoded `eth1`) and persist a `0.0.0.0/0` route via `${local.network_gw_ipv4}` in the active NetworkManager connection.
- A runtime guard (`ip route add` with a high metric) ensures nodes regain egress immediately, even before NetworkManager reapplies the profile, without disturbing an existing public default route.
- The route uses a higher metric so the public interface continues to be preferred on mixed deployments.

No manual `ip route add` commands are needed after reboots or DHCP renewals. If you roll your own images or bootstrap logic, make sure an equivalent persistent route exists or the nodes will lose outbound connectivity the next time the DHCP lease renews.
