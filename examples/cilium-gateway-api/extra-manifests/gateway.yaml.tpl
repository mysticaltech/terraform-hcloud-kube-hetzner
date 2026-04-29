apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: cilium-gateway
  namespace: default
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-staging-gateway
spec:
  gatewayClassName: cilium
  listeners:
    - name: http
      hostname: ${gateway_hostname}
      port: 80
      protocol: HTTP
      allowedRoutes:
        namespaces:
          from: Same
    - name: https
      hostname: ${gateway_hostname}
      port: 443
      protocol: HTTPS
      tls:
        mode: Terminate
        certificateRefs:
          - name: cilium-gateway-tls
      allowedRoutes:
        namespaces:
          from: Same
