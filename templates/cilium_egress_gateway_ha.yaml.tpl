---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cilium-egress-ha
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cilium-egress-ha
rules:
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["cilium.io"]
    resources: ["ciliumegressgatewaypolicies"]
    verbs: ["get", "list", "watch", "patch", "update"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cilium-egress-ha
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cilium-egress-ha
subjects:
  - kind: ServiceAccount
    name: cilium-egress-ha
    namespace: kube-system
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: cilium-egress-ha
  namespace: kube-system
data:
  reconcile.sh: |-
    #!/bin/sh
    set -eu

    EGRESS_NODE_SELECTOR='node.kubernetes.io/role=egress'
    POLICY_SELECTOR='kube-hetzner.io/egress-ha=true'
    SLEEP_SECONDS=15

    while true; do
      if ! kubectl get crd ciliumegressgatewaypolicies.cilium.io >/dev/null 2>&1; then
        sleep "$SLEEP_SECONDS"
        continue
      fi

      active_node="$(kubectl get nodes -l "$EGRESS_NODE_SELECTOR" --no-headers 2>/dev/null | awk '$2 ~ /^Ready/ {print $1; exit}')"
      if [ -z "$active_node" ]; then
        echo "cilium-egress-ha: no Ready egress node found"
        sleep "$SLEEP_SECONDS"
        continue
      fi

      policies="$(kubectl get ciliumegressgatewaypolicies.cilium.io -A -l "$POLICY_SELECTOR" -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)"
      if [ -z "$policies" ]; then
        sleep "$SLEEP_SECONDS"
        continue
      fi

      printf '%s\n' "$policies" | while IFS=' ' read -r namespace policy; do
        [ -z "$namespace" ] && continue
        patch='{"spec":{"egressGateway":{"nodeSelector":{"matchLabels":{"kubernetes.io/hostname":"'"$active_node"'"}}}}}'
        kubectl patch ciliumegressgatewaypolicies.cilium.io "$policy" -n "$namespace" --type merge -p "$patch" >/dev/null
        kubectl annotate ciliumegressgatewaypolicies.cilium.io "$policy" -n "$namespace" kube-hetzner.io/egress-ha-last-node="$active_node" --overwrite >/dev/null
      done

      sleep "$SLEEP_SECONDS"
    done
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cilium-egress-ha
  namespace: kube-system
  labels:
    app.kubernetes.io/name: cilium-egress-ha
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: cilium-egress-ha
  template:
    metadata:
      labels:
        app.kubernetes.io/name: cilium-egress-ha
    spec:
      serviceAccountName: cilium-egress-ha
      priorityClassName: system-cluster-critical
      tolerations:
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
          effect: NoSchedule
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: node-role.kubernetes.io/control-plane
                    operator: Exists
      containers:
        - name: controller
          image: docker.io/bitnami/kubectl:1.31
          imagePullPolicy: IfNotPresent
          command: ["/bin/sh", "/scripts/reconcile.sh"]
          resources:
            requests:
              cpu: 10m
              memory: 32Mi
            limits:
              cpu: 100m
              memory: 128Mi
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            runAsNonRoot: true
            runAsUser: 1001
          volumeMounts:
            - name: script
              mountPath: /scripts
              readOnly: true
      volumes:
        - name: script
          configMap:
            name: cilium-egress-ha
            defaultMode: 0755
