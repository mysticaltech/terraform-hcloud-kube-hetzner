---
apiVersion: v1
kind: Service
metadata:
  name: hcloud-cloud-controller-manager-metrics
  namespace: kube-system
  labels:
    app.kubernetes.io/name: hcloud-cloud-controller-manager
spec:
  selector:
    app.kubernetes.io/name: hcloud-cloud-controller-manager
  ports:
    - name: metrics
      port: 8233
      targetPort: metrics
      protocol: TCP
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: hcloud-cloud-controller-manager
  namespace: kube-system
  labels:
    app.kubernetes.io/name: hcloud-cloud-controller-manager
spec:
  namespaceSelector:
    matchNames:
      - kube-system
  selector:
    matchLabels:
      app.kubernetes.io/name: hcloud-cloud-controller-manager
  endpoints:
    - port: metrics
      path: /metrics
      interval: 30s
---
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: hcloud-cloud-controller-manager
  namespace: kube-system
  labels:
    app.kubernetes.io/name: hcloud-cloud-controller-manager
spec:
  groups:
    - name: hcloud-cloud-controller-manager.load-balancer
      rules:
        - alert: HCloudLoadBalancerUnhealthyTargets
          expr: sum(hcloud_load_balancer_target_healthy == 0) > 0
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: Hetzner load balancer has unhealthy targets
            description: One or more Hetzner load balancer targets report unhealthy state via CCM metrics.
