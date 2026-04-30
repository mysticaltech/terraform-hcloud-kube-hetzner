locals {
  validation_locations_by_region = {
    eu-central   = ["fsn1", "hel1", "nbg1"]
    us-east      = ["ash"]
    us-west      = ["hil"]
    ap-southeast = ["sin"]
  }

  validation_control_plane_count = length(var.control_plane_nodepools) > 0 ? sum([
    for nodepool in var.control_plane_nodepools :
    length(coalesce(nodepool.nodes, {})) + coalesce(nodepool.count, 0)
  ]) : 0

  validation_agent_count = length(var.agent_nodepools) > 0 ? sum([
    for nodepool in var.agent_nodepools :
    length(coalesce(nodepool.nodes, {})) + coalesce(nodepool.count, 0)
  ]) : 0

  validation_autoscaler_max_count = length(var.autoscaler_nodepools) > 0 ? sum([
    for nodepool in var.autoscaler_nodepools : nodepool.max_nodes
  ]) : 0

  validation_is_single_node_cluster = (
    local.validation_control_plane_count +
    local.validation_agent_count +
    local.validation_autoscaler_max_count
  ) == 1
  validation_using_klipper_lb = var.enable_klipper_metal_lb || local.validation_is_single_node_cluster
  validation_has_external_load_balancer_base = (
    local.validation_using_klipper_lb ||
    var.ingress_controller == "none"
  )
  validation_combine_load_balancers_effective = (
    var.reuse_control_plane_load_balancer &&
    var.enable_control_plane_load_balancer &&
    !local.validation_has_external_load_balancer_base
  )
  validation_has_external_load_balancer = (
    local.validation_has_external_load_balancer_base ||
    local.validation_combine_load_balancers_effective
  )
  validation_uses_load_balancer_location = (
    var.enable_control_plane_load_balancer ||
    (!local.validation_has_external_load_balancer && var.multinetwork_mode != "cilium_public_overlay")
  )

  validation_tailnet_ipv4_candidate_cidrs = compact([
    var.network_ipv4_cidr,
    var.cluster_ipv4_cidr,
    var.service_ipv4_cidr,
  ])
  validation_tailnet_ipv6_candidate_cidrs = compact([
    var.cluster_ipv6_cidr,
    var.service_ipv6_cidr,
  ])
  validation_tailnet_ipv4_cidr_starts_inside = [
    for cidr in local.validation_tailnet_ipv4_candidate_cidrs : cidr
    if can(cidrhost(cidr, 0)) && can(regex("^100\\.(6[4-9]|[7-9][0-9]|1[0-1][0-9]|12[0-7])\\.", cidrhost(cidr, 0)))
  ]
  validation_tailnet_ipv6_cidr_starts_inside = [
    for cidr in local.validation_tailnet_ipv6_candidate_cidrs : cidr
    if can(cidrhost(cidr, 0)) && can(regex("^fd7a:115c:a1e0:", lower(cidrhost(cidr, 0))))
  ]

  validation_control_plane_locations = concat(
    [
      for nodepool in var.control_plane_nodepools : nodepool.location
      if coalesce(nodepool.count, 0) > 0
    ],
    flatten([
      for nodepool in var.control_plane_nodepools : [
        for _, node in coalesce(nodepool.nodes, {}) :
        coalesce(node.location, nodepool.location)
      ]
    ])
  )

  validation_agent_locations = concat(
    [
      for nodepool in var.agent_nodepools : nodepool.location
      if coalesce(nodepool.count, 0) > 0 && (nodepool.network_scope == "primary" ? 0 : coalesce(nodepool.network_id, 0)) == 0
    ],
    flatten([
      for nodepool in var.agent_nodepools : [
        for _, node in coalesce(nodepool.nodes, {}) :
        coalesce(node.location, nodepool.location)
        if(try(coalesce(node.network_scope, nodepool.network_scope), null) == "primary" ? 0 : coalesce(node.network_id, nodepool.network_id, 0)) == 0
      ]
    ])
  )

  validation_autoscaler_locations = [
    for nodepool in var.autoscaler_nodepools : nodepool.location
    if(nodepool.network_scope == "primary" ? 0 : coalesce(nodepool.network_id, 0)) == 0
  ]

  validation_nat_router_locations = var.nat_router == null ? [] : compact([
    var.nat_router.location,
    try(var.nat_router.standby_location, "")
  ])

  validation_all_locations = concat(
    local.validation_control_plane_locations,
    local.validation_agent_locations,
    local.validation_autoscaler_locations,
    local.validation_nat_router_locations,
    local.validation_uses_load_balancer_location ? [var.load_balancer_location] : []
  )

  validation_control_plane_server_types = concat(
    [for nodepool in var.control_plane_nodepools : nodepool.server_type],
    flatten([
      for nodepool in var.control_plane_nodepools : [
        for _, node in coalesce(nodepool.nodes, {}) :
        coalesce(node.server_type, nodepool.server_type)
      ]
    ])
  )

  validation_agent_server_types = concat(
    [for nodepool in var.agent_nodepools : nodepool.server_type],
    flatten([
      for nodepool in var.agent_nodepools : [
        for _, node in coalesce(nodepool.nodes, {}) :
        coalesce(node.server_type, nodepool.server_type)
      ]
    ])
  )

  validation_autoscaler_server_types = [
    for nodepool in var.autoscaler_nodepools : nodepool.server_type
  ]

  validation_all_server_types = concat(
    local.validation_control_plane_server_types,
    local.validation_agent_server_types,
    local.validation_autoscaler_server_types
  )

  validation_primary_network_agent_subnet_indexes = (
    var.network_subnet_mode == "per_nodepool"
    ? range(length(var.agent_nodepools))
    : [0]
  )
  validation_primary_network_control_plane_subnet_indexes = (
    var.network_subnet_mode == "per_nodepool"
    ? [
      for index in range(length(var.control_plane_nodepools)) :
      var.subnet_count - 1 - index
    ]
    : [var.subnet_count - 1]
  )
  validation_reserved_primary_network_subnet_indexes = distinct(concat(
    local.validation_primary_network_agent_subnet_indexes,
    local.validation_primary_network_control_plane_subnet_indexes
  ))

  validation_external_agent_network_ids = distinct(flatten([
    for nodepool in var.agent_nodepools : concat(
      (nodepool.network_scope == "primary" ? 0 : coalesce(nodepool.network_id, 0)) == 0 ? [] : [coalesce(nodepool.network_id, 0)],
      [
        for _, node in coalesce(nodepool.nodes, {}) :
        coalesce(node.network_id, nodepool.network_id, 0)
        if(try(coalesce(node.network_scope, nodepool.network_scope), null) == "primary" ? 0 : coalesce(node.network_id, nodepool.network_id, 0)) != 0
      ]
    )
  ]))

  validation_external_autoscaler_network_ids = distinct([
    for nodepool in var.autoscaler_nodepools :
    coalesce(nodepool.network_id, 0)
    if(nodepool.network_scope == "primary" ? 0 : coalesce(nodepool.network_id, 0)) != 0
  ])

  validation_static_agent_network_scopes = flatten([
    for nodepool in var.agent_nodepools : concat(
      [
        for _ in range(max(0, floor(coalesce(nodepool.count, 0)))) :
        coalesce(nodepool.network_scope, "__unset")
      ],
      [
        for _, node in coalesce(nodepool.nodes, {}) :
        coalesce(node.network_scope, nodepool.network_scope, "__unset")
      ]
    )
  ])

  validation_static_agent_network_scopes_are_explicit = alltrue([
    for scope in local.validation_static_agent_network_scopes :
    contains(["primary", "external"], scope)
  ])

  validation_static_agents_all_primary_by_scope = alltrue([
    for scope in local.validation_static_agent_network_scopes :
    scope == "primary"
  ])

  validation_autoscaler_network_scopes = [
    for nodepool in var.autoscaler_nodepools :
    nodepool.max_nodes <= 0 ? "primary" : coalesce(nodepool.network_scope, "__unset")
  ]

  validation_autoscaler_network_scopes_are_explicit = alltrue([
    for scope in local.validation_autoscaler_network_scopes :
    contains(["primary", "external"], scope)
  ])

  validation_autoscalers_all_primary_by_scope = alltrue([
    for scope in local.validation_autoscaler_network_scopes :
    scope == "primary"
  ])

  validation_referenced_network_ids = distinct(concat(
    [0],
    var.extra_network_ids,
    local.validation_external_agent_network_ids,
    local.validation_external_autoscaler_network_ids
  ))

  validation_network_attachment_count_by_network = {
    for network_id in local.validation_referenced_network_ids :
    network_id => (
      (
        network_id == 0 ||
        contains(var.extra_network_ids, network_id) ||
        (
          var.multinetwork_mode != "cilium_public_overlay" &&
          var.node_transport_mode != "tailscale" &&
          contains(local.validation_external_agent_network_ids, network_id)
        )
      ) ? local.validation_control_plane_count : 0
      ) + sum(concat([0], flatten([
        for nodepool in var.agent_nodepools : concat(
          [
            (
              nodepool.count == null ? 0 : (
                (nodepool.network_scope == "primary" ? 0 : coalesce(nodepool.network_id, 0)) == network_id ||
                contains(var.extra_network_ids, network_id)
                ? nodepool.count
                : 0
              )
            )
          ],
          [
            for _, node in coalesce(nodepool.nodes, {}) :
            (
              (try(coalesce(node.network_scope, nodepool.network_scope), null) == "primary" ? 0 : coalesce(node.network_id, nodepool.network_id, 0)) == network_id ||
              contains(var.extra_network_ids, network_id)
              ? 1
              : 0
            )
          ]
        )
      ]))) + (
      sum(concat([0], [
        for nodepool in var.autoscaler_nodepools :
        (nodepool.network_scope == "primary" ? 0 : coalesce(nodepool.network_id, 0)) == network_id ? nodepool.max_nodes : 0
      ]))
      ) + (
      network_id == 0 && var.nat_router != null ? (try(var.nat_router.enable_redundancy, false) ? 2 : 1) : 0
      ) + (
      network_id == 0 && var.enable_control_plane_load_balancer ? 1 : 0
      ) + (
      network_id == 0 && !local.validation_has_external_load_balancer && var.multinetwork_mode != "cilium_public_overlay" && var.node_transport_mode != "tailscale" ? 1 : 0
    )
  }

  validation_control_plane_placement_group_keys = flatten([
    for nodepool in var.control_plane_nodepools : concat(
      [
        for node_index in range(max(0, floor(coalesce(nodepool.count, 0)))) :
        nodepool.placement_group == null ? "compat:${nodepool.placement_group_index + floor(node_index / 10)}" : "named:${nodepool.placement_group}"
      ],
      [
        for _, node in coalesce(nodepool.nodes, {}) :
        node.placement_group != null ? "named:${node.placement_group}" : (
          nodepool.placement_group != null ? "named:${nodepool.placement_group}" : "compat:${coalesce(node.placement_group_index, nodepool.placement_group_index)}"
        )
      ]
    )
  ])
  validation_agent_placement_group_keys = flatten([
    for nodepool in var.agent_nodepools : concat(
      [
        for node_index in range(max(0, floor(coalesce(nodepool.count, 0)))) :
        nodepool.placement_group == null ? "compat:${nodepool.placement_group_index + floor(node_index / 10)}" : "named:${nodepool.placement_group}"
      ],
      [
        for _, node in coalesce(nodepool.nodes, {}) :
        node.placement_group != null ? "named:${node.placement_group}" : (
          nodepool.placement_group != null ? "named:${nodepool.placement_group}" : "compat:${coalesce(node.placement_group_index, nodepool.placement_group_index)}"
        )
      ]
    )
  ])

  validation_module_created_placement_group_count = (
    local.control_plane_placement_compat_groups +
    length(local.control_plane_groups) +
    local.agent_placement_compat_groups +
    length(local.agent_placement_groups)
  )
}
