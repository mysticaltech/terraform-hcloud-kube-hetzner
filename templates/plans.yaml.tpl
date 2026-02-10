---
# Doc: https://rancher.com/docs/k3s/latest/en/upgrades/automated/
# agent plan
apiVersion: upgrade.cattle.io/v1
kind: Plan
metadata:
  name: k3s-agent
  namespace: system-upgrade
  labels:
    k3s_upgrade: agent
spec:
  concurrency: 1
  %{~ if version == "" ~}
  channel: https://update.k3s.io/v1-release/channels/${channel}
  %{~ else ~}
  version: ${version}
  %{~ endif ~}
  serviceAccountName: system-upgrade
  nodeSelector:
    matchExpressions:
      - {key: k3s_upgrade, operator: Exists}
      - {key: k3s_upgrade, operator: NotIn, values: ["disabled", "false"]}
      - {key: node-role.kubernetes.io/control-plane, operator: NotIn, values: ["true"]}
      - {key: kured, operator: NotIn, values: ["rebooting"]}
  tolerations:
    - {key: server-usage, effect: NoSchedule, operator: Equal, value: storage}
    - {operator: Exists}
  prepare:
    image: rancher/k3s-upgrade
    args: ["prepare", "k3s-server"]
  %{ if drain }drain:
    force: true
    disableEviction: ${disable_eviction}
    skipWaitForDeleteTimeout: 60%{ endif }
  %{ if !drain }cordon: true%{ endif }
  %{~ if upgrade_window != null ~}
  window:
    %{~ if length(upgrade_window.days) > 0 ~}
    days:
      %{~ for day in upgrade_window.days ~}
      - ${day}
      %{~ endfor ~}
    %{~ endif ~}
    %{~ if upgrade_window.startTime != "" ~}
    startTime: "${upgrade_window.startTime}"
    %{~ endif ~}
    %{~ if upgrade_window.endTime != "" ~}
    endTime: "${upgrade_window.endTime}"
    %{~ endif ~}
    %{~ if upgrade_window.timeZone != "" ~}
    timeZone: "${upgrade_window.timeZone}"
    %{~ endif ~}
  %{~ endif ~}
  upgrade:
    image: rancher/k3s-upgrade
---
# server plan
apiVersion: upgrade.cattle.io/v1
kind: Plan
metadata:
  name: k3s-server
  namespace: system-upgrade
  labels:
    k3s_upgrade: server
spec:
  concurrency: 1
  %{~ if version == "" ~}
  channel: https://update.k3s.io/v1-release/channels/${channel}
  %{~ else ~}
  version: ${version}
  %{~ endif ~}
  serviceAccountName: system-upgrade
  nodeSelector:
    matchExpressions:
      - {key: k3s_upgrade, operator: Exists}
      - {key: k3s_upgrade, operator: NotIn, values: ["disabled", "false"]}
      - {key: node-role.kubernetes.io/control-plane, operator: In, values: ["true"]}
      - {key: kured, operator: NotIn, values: ["rebooting"]}
  tolerations:
    - {key: node-role.kubernetes.io/control-plane, effect: NoSchedule, operator: Exists}
    - {key: CriticalAddonsOnly, effect: NoExecute, operator: Exists}
  cordon: true
  %{~ if upgrade_window != null ~}
  window:
    %{~ if length(upgrade_window.days) > 0 ~}
    days:
      %{~ for day in upgrade_window.days ~}
      - ${day}
      %{~ endfor ~}
    %{~ endif ~}
    %{~ if upgrade_window.startTime != "" ~}
    startTime: "${upgrade_window.startTime}"
    %{~ endif ~}
    %{~ if upgrade_window.endTime != "" ~}
    endTime: "${upgrade_window.endTime}"
    %{~ endif ~}
    %{~ if upgrade_window.timeZone != "" ~}
    timeZone: "${upgrade_window.timeZone}"
    %{~ endif ~}
  %{~ endif ~}
  upgrade:
    image: rancher/k3s-upgrade
