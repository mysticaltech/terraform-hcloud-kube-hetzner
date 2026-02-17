---
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
    k8s-app: cluster-autoscaler
  name: cluster-autoscaler
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cluster-autoscaler
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
    k8s-app: cluster-autoscaler
rules:
  - apiGroups: [""]
    resources: ["events", "endpoints"]
    verbs: ["create", "patch"]
  - apiGroups: [""]
    resources: ["pods/eviction"]
    verbs: ["create"]
  - apiGroups: [""]
    resources: ["pods/status"]
    verbs: ["update"]
  - apiGroups: [""]
    resources: ["endpoints"]
    resourceNames: ["cluster-autoscaler"]
    verbs: ["get", "update"]
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["watch", "list", "get", "update"]
  - apiGroups: [""]
    resources:
      - "namespaces"
      - "pods"
      - "services"
      - "replicationcontrollers"
      - "persistentvolumeclaims"
      - "persistentvolumes"
    verbs: ["watch", "list", "get"]
  - apiGroups: ["extensions"]
    resources: ["replicasets", "daemonsets"]
    verbs: ["watch", "list", "get"]
  - apiGroups: ["policy"]
    resources: ["poddisruptionbudgets"]
    verbs: ["watch", "list"]
  - apiGroups: ["apps"]
    resources: ["statefulsets", "replicasets", "daemonsets"]
    verbs: ["watch", "list", "get"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses", "csinodes", "csistoragecapacities", "csidrivers", "volumeattachments"]
    verbs: ["watch", "list", "get"]
  - apiGroups: ["batch", "extensions"]
    resources: ["jobs"]
    verbs: ["get", "list", "watch", "patch"]
  - apiGroups: ["coordination.k8s.io"]
    resources: ["leases"]
    verbs: ["create"]
  - apiGroups: ["coordination.k8s.io"]
    resourceNames: ["cluster-autoscaler"]
    resources: ["leases"]
    verbs: ["get", "update"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: cluster-autoscaler
  namespace: kube-system
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
    k8s-app: cluster-autoscaler
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["create","list","watch"]
  - apiGroups: [""]
    resources: ["configmaps"]
    resourceNames: ["cluster-autoscaler-status", "cluster-autoscaler-priority-expander"]
    verbs: ["delete", "get", "update", "watch"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cluster-autoscaler
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
    k8s-app: cluster-autoscaler
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-autoscaler
subjects:
  - kind: ServiceAccount
    name: cluster-autoscaler
    namespace: kube-system

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: cluster-autoscaler
  namespace: kube-system
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
    k8s-app: cluster-autoscaler
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: cluster-autoscaler
subjects:
  - kind: ServiceAccount
    name: cluster-autoscaler
    namespace: kube-system

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cluster-autoscaler
  namespace: kube-system
  labels:
    app: cluster-autoscaler
spec:
  replicas: ${ca_replicas}
  selector:
    matchLabels:
      app: cluster-autoscaler
  template:
    metadata:
      labels:
        app: cluster-autoscaler
      annotations:
        prometheus.io/scrape: 'true'
        prometheus.io/port: '8085'
    spec:
      serviceAccountName: cluster-autoscaler
      tolerations:
        - effect: NoSchedule
          key: node-role.kubernetes.io/control-plane

      # Node affinity is used to force cluster-autoscaler to stick
      # to the control-plane node. This allows the cluster to reliably downscale
      # to zero worker nodes when needed.
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: node-role.kubernetes.io/control-plane
                    operator: Exists
      containers:
        - image: ${ca_image}:${ca_version}
          name: cluster-autoscaler
          %{~ if ca_resource_limits ~}
          resources:
            limits:
              cpu: ${ca_resources.limits.cpu}
              memory: ${ca_resources.limits.memory}
            requests:
              cpu: ${ca_resources.requests.cpu}
              memory: ${ca_resources.requests.memory}
          %{~ endif ~}
          ports:
            - containerPort: 8085
          command:
            - ./cluster-autoscaler
            - --v=${cluster_autoscaler_log_level}
            - --logtostderr=${cluster_autoscaler_log_to_stderr}
            - --stderrthreshold=${cluster_autoscaler_stderr_threshold}
            - --cloud-provider=hetzner
            %{~ for pool in node_pools ~}
            - --nodes=${pool.min_nodes}:${pool.max_nodes}:${pool.server_type}:${pool.location}:${cluster_name}${pool.name}
            %{~ endfor ~}
            %{~ for extra_arg in cluster_autoscaler_extra_args ~}
            - ${extra_arg}
            %{~ endfor ~}
          env:
          - name: HCLOUD_TOKEN
            valueFrom:
                secretKeyRef:
                  name: hcloud
                  key: token
          - name: HCLOUD_CLOUD_INIT
            value: ${cloudinit_config}
          - name: HCLOUD_CLUSTER_CONFIG
            value: ${cluster_config}
          - name: HCLOUD_SSH_KEY
            value: '${ssh_key}'
          - name: HCLOUD_IMAGE
            value: '${snapshot_id}'
          - name: HCLOUD_NETWORK
            value: '${ipv4_subnet_id}'
          - name: HCLOUD_FIREWALL
            value: '${firewall_id}'
          - name: HCLOUD_PUBLIC_IPV4
            value: '${enable_ipv4}'
          - name: HCLOUD_PUBLIC_IPV6
            value: '${enable_ipv6}'
          %{~ if cluster_autoscaler_server_creation_timeout != "" ~}
          - name: HCLOUD_SERVER_CREATION_TIMEOUT
            value: '${cluster_autoscaler_server_creation_timeout}'
          %{~ endif ~}
          volumeMounts:
            - name: ssl-certs
              mountPath: /etc/ssl/certs
              readOnly: true
          imagePullPolicy: "Always"
      volumes:
        - name: ssl-certs
          hostPath:
            path: "/etc/ssl/certs" # right place on MicroOS?
