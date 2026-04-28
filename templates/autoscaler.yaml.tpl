---
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
    k8s-app: ${autoscaler_name}
  name: ${autoscaler_name}
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: ${autoscaler_name}
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
    k8s-app: ${autoscaler_name}
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
    resourceNames: ["${autoscaler_name}"]
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
    resourceNames: ["${leader_election_resource_name}"]
    resources: ["leases"]
    verbs: ["get", "update"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ${autoscaler_name}
  namespace: kube-system
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
    k8s-app: ${autoscaler_name}
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["create","list","watch"]
  - apiGroups: [""]
    resources: ["configmaps"]
    resourceNames: ["${autoscaler_name}-status", "cluster-autoscaler-priority-expander"]
    verbs: ["delete", "get", "update", "watch"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ${autoscaler_name}
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
    k8s-app: ${autoscaler_name}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: ${autoscaler_name}
subjects:
  - kind: ServiceAccount
    name: ${autoscaler_name}
    namespace: kube-system

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${autoscaler_name}
  namespace: kube-system
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
    k8s-app: ${autoscaler_name}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: ${autoscaler_name}
subjects:
  - kind: ServiceAccount
    name: ${autoscaler_name}
    namespace: kube-system

---
apiVersion: v1
kind: Service
metadata:
  name: ${autoscaler_name}-metrics
  namespace: kube-system
  labels:
    app: ${autoscaler_name}
spec:
  type: NodePort
  selector:
    app: ${autoscaler_name}
  ports:
    - name: metrics
      protocol: TCP
      port: 8085
      targetPort: 8085
      nodePort: ${metrics_node_port}

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${autoscaler_name}
  namespace: kube-system
  labels:
    app: ${autoscaler_name}
spec:
  replicas: ${ca_replicas}
  selector:
    matchLabels:
      app: ${autoscaler_name}
  template:
    metadata:
      labels:
        app: ${autoscaler_name}
      annotations:
        prometheus.io/scrape: 'true'
        prometheus.io/port: '8085'
    spec:
      serviceAccountName: ${autoscaler_name}
      tolerations:
        - effect: NoSchedule
          key: node-role.kubernetes.io/control-plane
        %{~ if length(cluster_autoscaler_tolerations) > 0 ~}
${indent(8, yamlencode(cluster_autoscaler_tolerations))}
        %{~ endif ~}

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
            - --leader-elect-resource-name=${leader_election_resource_name}
            - --status-config-map-name=${autoscaler_name}-status
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
