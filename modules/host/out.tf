output "ipv4_address" {
  value = hcloud_server.server.ipv4_address
}

output "ipv6_address" {
  value = hcloud_server.server.ipv6_address
}

output "private_ipv4_address" {
  value = try(one(hcloud_server.server.network).ip, "")
}

output "name" {
  value = hcloud_server.server.name
}

output "id" {
  value = hcloud_server.server.id
}

output "domain_assignments" {
  description = "Assignment of domain to the primary IP of the server"
  value = [
    for rdns in hcloud_rdns.server : {
      domain = rdns.dns_ptr
      ips    = [rdns.ip_address]
    }
  ]
}

output "tailscale_ip_address" {
  description = "The Tailscale Tailnet IP address of the server"
  value       = local.tailscale_ip
}

output "tailscale_advertised_routes" {
  description = "List of routes advertised by the node"
  value       = local.tailscale_routes
}
