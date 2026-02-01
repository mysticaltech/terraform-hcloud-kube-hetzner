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
            - "--allocate-node-cidrs=true"
            - "--cluster-cidr=${cluster_cidr_ipv4}"
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
