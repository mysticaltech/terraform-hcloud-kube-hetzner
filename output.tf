output "cluster_name" {
  value       = var.cluster_name
  description = "Shared suffix for all resources belonging to this cluster."
}

output "network_id" {
  value       = data.hcloud_network.k3s.id
  description = "The ID of the HCloud network."
}

output "ssh_key_id" {
  value       = local.hcloud_ssh_key_id
  description = "The ID of the HCloud SSH key."
}

output "control_planes_public_ipv4" {
  value = [
    for obj in module.control_planes : obj.ipv4_address
  ]
  description = "The public IPv4 addresses of the controlplane servers."
}

output "control_planes_public_ipv6" {
  value = [
    for obj in module.control_planes : obj.ipv6_address
  ]
  description = "The public IPv6 addresses of the controlplane servers."
}

output "agents_public_ipv4" {
  value = [
    for obj in module.agents : obj.ipv4_address
  ]
  description = "The public IPv4 addresses of the agent servers."
}

output "agents_public_ipv6" {
  value = [
    for obj in module.agents : obj.ipv6_address
  ]
  description = "The public IPv6 addresses of the agent servers."
}

output "ingress_public_ipv4" {
  description = "The public IPv4 address of the Hetzner load balancer (with fallback to first control plane node)"
  value       = local.has_external_load_balancer ? local.first_control_plane_ip : hcloud_load_balancer.cluster[0].ipv4
}

output "ingress_public_ipv6" {
  description = "The public IPv6 address of the Hetzner load balancer (with fallback to first control plane node)"
  value       = local.has_external_load_balancer ? module.control_planes[keys(module.control_planes)[0]].ipv6_address : (var.load_balancer_disable_ipv6 ? null : hcloud_load_balancer.cluster[0].ipv6)
}

output "lb_control_plane_ipv4" {
  description = "The public IPv4 address of the Hetzner control plane load balancer"
  value       = one(hcloud_load_balancer.control_plane[*].ipv4)
}

output "lb_control_plane_ipv6" {
  description = "The public IPv6 address of the Hetzner control plane load balancer"
  value       = one(hcloud_load_balancer.control_plane[*].ipv6)
}

output "k3s_endpoint" {
  description = "A controller endpoint to register new nodes"
  value       = local.k3s_endpoint
}

output "k3s_token" {
  description = "The k3s token to register new nodes"
  value       = local.k3s_token
  sensitive   = true
}

output "control_plane_nodes" {
  description = "The control plane nodes"
  value       = [for node in module.control_planes : node]
}

output "agent_nodes" {
  description = "The agent nodes"
  value       = [for node in module.agents : node]
}

output "domain_assignments" {
  description = "Assignments of domains to IPs based on reverse DNS"
  value = concat(
    # Propagate domain assignments from control plane and agent nodes.
    flatten([
      for node in concat(values(module.control_planes), values(module.agents)) :
      node.domain_assignments
    ]),
    # Get assignments from floating IPs.
    [for rdns in hcloud_rdns.agents : {
      domain = rdns.dns_ptr
      ips    = [rdns.ip_address]
    }]
  )
}

# Keeping for backward compatibility
output "kubeconfig_file" {
  value       = local.kubeconfig_external
  description = "Kubeconfig file content with external IP address, or internal IP address if only private ips are available"
  sensitive   = true
}

output "kubeconfig" {
  value       = local.kubeconfig_external
  description = "Kubeconfig file content with external IP address, or internal IP address if only private ips are available"
  sensitive   = true
}

output "kubeconfig_data" {
  description = "Structured kubeconfig data to supply to other providers"
  value       = local.kubeconfig_data
  sensitive   = true
}

output "cilium_values" {
  description = "Helm values.yaml used for Cilium"
  value       = local.cilium_values
  sensitive   = true
}

output "cert_manager_values" {
  description = "Helm values.yaml used for cert-manager"
  value       = local.cert_manager_values
  sensitive   = true
}

output "csi_driver_smb_values" {
  description = "Helm values.yaml used for SMB CSI driver"
  value       = local.csi_driver_smb_values
  sensitive   = true
}

output "longhorn_values" {
  description = "Helm values.yaml used for Longhorn"
  value       = local.longhorn_values
  sensitive   = true
}

output "traefik_values" {
  description = "Helm values.yaml used for Traefik"
  value       = local.traefik_values
  sensitive   = true
}

output "nginx_values" {
  description = "Helm values.yaml used for nginx-ingress"
  value       = local.nginx_values
  sensitive   = true
}

output "haproxy_values" {
  description = "Helm values.yaml used for HAProxy"
  value       = local.haproxy_values
  sensitive   = true
}

output "nat_router_public_ipv4" {
  description = "The address of the nat router, if it exists."
  value       = try(hcloud_server.nat_router[0].ipv4_address, null)
}
output "nat_router_public_ipv6" {
  description = "The address of the nat router, if it exists."
  value       = try(hcloud_server.nat_router[0].ipv6_address, null)
}
output "nat_router_public_ipv4_addresses" {
  description = "The addresses of all nat routers, if they exist."
  value       = [for nat_router in hcloud_server.nat_router : nat_router.ipv4_address]
}
output "nat_router_public_ipv6_addresses" {
  description = "The addresses of all nat routers, if they exist."
  value       = [for nat_router in hcloud_server.nat_router : nat_router.ipv6_address]
}
output "nat_router_username" {
  description = "The non-root user as which you can ssh into the router."
  value       = "nat-router" # hard-coded in cloud-init template.
}
output "nat_router_ssh_port" {
  description = "The non-root user as which you can ssh into the router."
  value       = var.ssh_port
}

output "vswitch_subnet" {
  description = "Attributes of the vSwitch subnet."
  value       = try(hcloud_network_subnet.vswitch_subnet[0], null)
}
