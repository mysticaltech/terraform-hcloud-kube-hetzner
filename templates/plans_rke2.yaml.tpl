# Server plan
apiVersion: upgrade.cattle.io/v1
kind: Plan
metadata:
  name: server-plan
  namespace: system-upgrade
  labels:
    rke2_upgrade: server
spec:
  concurrency: 1
  %{~ if version == "" ~}
  channel: https://update.rke2.io/v1-release/channels/${channel}
  %{~ else ~}
  version: ${version}
  %{~ endif ~}
  nodeSelector:
    matchExpressions:
        - {key: rke2_upgrade, operator: Exists}
        - {key: rke2_upgrade, operator: NotIn, values: ["disabled", "false"]}
        - {key: node-role.kubernetes.io/control-plane, operator: In, values: ["true"]}
        - {key: kured, operator: NotIn, values: ["rebooting"]}
  tolerations:
    - {key: node-role.kubernetes.io/control-plane, effect: NoSchedule, operator: Exists}
    - {key: CriticalAddonsOnly, effect: NoExecute, operator: Exists}
  serviceAccountName: system-upgrade
  cordon: true
  %{~ if upgrade_window != null ~}
  window:
    %{~ if length(try(upgrade_window.days, [])) > 0 ~}
    days:
      %{~ for day in try(upgrade_window.days, []) ~}
      - ${jsonencode(day)}
      %{~ endfor ~}
    %{~ endif ~}
    %{~ if coalesce(try(upgrade_window.startTime, ""), "") != "" ~}
    startTime: ${jsonencode(coalesce(try(upgrade_window.startTime, ""), ""))}
    %{~ endif ~}
    %{~ if coalesce(try(upgrade_window.endTime, ""), "") != "" ~}
    endTime: ${jsonencode(coalesce(try(upgrade_window.endTime, ""), ""))}
    %{~ endif ~}
    %{~ if coalesce(try(upgrade_window.timeZone, ""), "") != "" ~}
    timeZone: ${jsonencode(coalesce(try(upgrade_window.timeZone, ""), ""))}
    %{~ endif ~}
  %{~ endif ~}
  upgrade:
    image: rancher/rke2-upgrade
---
# Agent plan
apiVersion: upgrade.cattle.io/v1
kind: Plan
metadata:
  name: agent-plan
  namespace: system-upgrade
  labels:
    rke2_upgrade: agent
spec:
  concurrency: 1
  %{~ if version == "" ~}
  channel: https://update.rke2.io/v1-release/channels/${channel}
  %{~ else ~}
  version: ${version}
  %{~ endif ~}
  nodeSelector:
    matchExpressions:
      - {key: kubernetes.io/os, operator: In, values: ["linux"]}
      - {key: node-role.kubernetes.io/control-plane, operator: NotIn, values: ["true"]}
      # Optionally limit the upgrade to nodes that have an "rke2-upgrade" label, and
      # exclude nodes where the label value is "disabled" or "false". To upgrade all
      # agent nodes, remove the following two items.
      - {key: rke2_upgrade, operator: Exists}
      - {key: rke2_upgrade, operator: NotIn, values: ["disabled", "false"]}
      - {key: node-role.kubernetes.io/control-plane, operator: NotIn, values: ["true"]}
      - {key: kured, operator: NotIn, values: ["rebooting"]}
  prepare:
    args:
    - prepare
    - server-plan
    image: rancher/rke2-upgrade
  serviceAccountName: system-upgrade
  %{ if drain }drain:
   force: true
   disableEviction: ${disable_eviction}
   skipWaitForDeleteTimeout: 60%{ endif }
  %{ if !drain }cordon: true%{ endif }
  %{~ if upgrade_window != null ~}
  window:
    %{~ if length(try(upgrade_window.days, [])) > 0 ~}
    days:
      %{~ for day in try(upgrade_window.days, []) ~}
      - ${jsonencode(day)}
      %{~ endfor ~}
    %{~ endif ~}
    %{~ if coalesce(try(upgrade_window.startTime, ""), "") != "" ~}
    startTime: ${jsonencode(coalesce(try(upgrade_window.startTime, ""), ""))}
    %{~ endif ~}
    %{~ if coalesce(try(upgrade_window.endTime, ""), "") != "" ~}
    endTime: ${jsonencode(coalesce(try(upgrade_window.endTime, ""), ""))}
    %{~ endif ~}
    %{~ if coalesce(try(upgrade_window.timeZone, ""), "") != "" ~}
    timeZone: ${jsonencode(coalesce(try(upgrade_window.timeZone, ""), ""))}
    %{~ endif ~}
  %{~ endif ~}
  upgrade:
    image: rancher/rke2-upgrade
