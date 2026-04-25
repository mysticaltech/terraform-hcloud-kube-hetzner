---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hcloud-cloud-controller-manager
  namespace: kube-system
spec:
  template:
    spec:
      containers:
        - name: hcloud-cloud-controller-manager
          args:
            - "--cloud-provider=hcloud"
            - "--leader-elect=false"
            - "--allow-untagged-cloud"
            - "--route-reconciliation-period=30s"
%{if cluster_cidr_ipv4 != ""~}
            - "--allocate-node-cidrs=true"
            - "--cluster-cidr=${cluster_cidr_ipv4}"
%{endif~}
            - "--webhook-secure-port=0"
%{if using_klipper_lb~}
            - "--secure-port=10288"
%{endif~}
          env:
            - name: "HCLOUD_LOAD_BALANCERS_LOCATION"
              value: "${default_lb_location}"
            - name: "HCLOUD_LOAD_BALANCERS_USE_PRIVATE_IP"
              value: "true"
            - name: "HCLOUD_LOAD_BALANCERS_ENABLED"
              value: "${!using_klipper_lb}"
            - name: "HCLOUD_LOAD_BALANCERS_DISABLE_PRIVATE_INGRESS"
              value: "true"
%{if instances_address_family != "ipv4"~}
            - name: "HCLOUD_INSTANCES_ADDRESS_FAMILY"
              value: "${instances_address_family}"
%{endif~}
      tolerations:
        - key: "node.cloudprovider.kubernetes.io/uninitialized"
          value: "true"
          effect: "NoSchedule"
        - key: "CriticalAddonsOnly"
          operator: "Exists"
        - key: "node-role.kubernetes.io/master"
          operator: "Exists"
          effect: "NoSchedule"
        - key: "node-role.kubernetes.io/control-plane"
          operator: "Exists"
          effect: "NoSchedule"
        - key: "node.kubernetes.io/not-ready"
          effect: "NoSchedule"
        - key: "node.kubernetes.io/not-ready"
          effect: "NoExecute"
        - key: "node.cilium.io/agent-not-ready"
          operator: "Exists"
          effect: "NoSchedule"
