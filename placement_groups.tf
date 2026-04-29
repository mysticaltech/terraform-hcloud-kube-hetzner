locals {
  control_plane_placement_compat_groups = max(0, concat(
    [
      for cp_pool in var.control_plane_nodepools :
      cp_pool.placement_group_index + max(1, ceil(coalesce(cp_pool.count, 0) / 10)) if cp_pool.placement_group_index != null && cp_pool.placement_group == null
    ],
    flatten([
      for cp_pool in var.control_plane_nodepools : [
        for _, node_config in coalesce(cp_pool.nodes, {}) :
        coalesce(node_config.placement_group_index, cp_pool.placement_group_index) + 1
        if(node_config.placement_group != null ? node_config.placement_group : cp_pool.placement_group) == null
      ]
    ])
  )...)
  control_plane_groups = toset(
    concat(
      [
        for cp_pool in var.control_plane_nodepools :
        cp_pool.placement_group if cp_pool.placement_group != null
      ],
      flatten([
        for cp_pool in var.control_plane_nodepools : [
          for _, node_config in coalesce(cp_pool.nodes, {}) :
          node_config.placement_group if node_config.placement_group != null
        ]
      ])
    )
  )
  agent_placement_compat_groups = max(0, concat(
    [
      for ag_pool in var.agent_nodepools :
      ag_pool.placement_group_index + max(1, ceil(coalesce(ag_pool.count, 0) / 10)) if ag_pool.placement_group_index != null && ag_pool.placement_group == null
    ],
    flatten([
      for ag_pool in var.agent_nodepools : [
        for _, node_config in coalesce(ag_pool.nodes, {}) :
        coalesce(node_config.placement_group_index, ag_pool.placement_group_index) + 1
        if(node_config.placement_group != null ? node_config.placement_group : ag_pool.placement_group) == null
      ]
    ])
  )...)
  agent_placement_groups = toset(
    concat(
      [
        for ag_pool in var.agent_nodepools :
        ag_pool.placement_group if ag_pool.placement_group != null
      ],
      concat(
        [
          for ag_pool in var.agent_nodepools :
          [
            for node, node_config in coalesce(ag_pool.nodes, {}) :
            node_config.placement_group if node_config.placement_group != null
          ]
        ]
      )...
    )
  )
}

resource "hcloud_placement_group" "control_plane" {
  count  = var.enable_placement_groups ? local.control_plane_placement_compat_groups : 0
  name   = "${var.cluster_name}-control-plane-${count.index + 1}"
  labels = local.labels
  type   = "spread"
}

resource "hcloud_placement_group" "control_plane_named" {
  for_each = var.enable_placement_groups ? local.control_plane_groups : toset([])
  name     = "${var.cluster_name}-control-plane-${each.key}"
  labels   = local.labels
  type     = "spread"
}

resource "hcloud_placement_group" "agent" {
  count  = var.enable_placement_groups ? local.agent_placement_compat_groups : 0
  name   = "${var.cluster_name}-agent-${count.index + 1}"
  labels = local.labels
  type   = "spread"
}

resource "hcloud_placement_group" "agent_named" {
  for_each = var.enable_placement_groups ? local.agent_placement_groups : toset([])
  name     = "${var.cluster_name}-agent-${each.key}"
  labels   = local.labels
  type     = "spread"
}
