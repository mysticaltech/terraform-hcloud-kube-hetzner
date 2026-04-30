output "ipv4_address" {
  value      = hcloud_server.server.ipv4_address
  depends_on = [terraform_data.initial_readiness, terraform_data.os_upgrade_timer]
}

output "ipv6_address" {
  value      = hcloud_server.server.ipv6_address
  depends_on = [terraform_data.initial_readiness, terraform_data.os_upgrade_timer]
}

output "private_ipv4_address" {
  value      = try(one(hcloud_server.server.network).ip, "")
  depends_on = [terraform_data.initial_readiness, terraform_data.os_upgrade_timer]
}

output "name" {
  value      = hcloud_server.server.name
  depends_on = [terraform_data.initial_readiness, terraform_data.os_upgrade_timer]
}

output "id" {
  value      = hcloud_server.server.id
  depends_on = [terraform_data.initial_readiness, terraform_data.os_upgrade_timer]
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
