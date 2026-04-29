apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: echo
  namespace: default
spec:
  parentRefs:
    - name: cilium-gateway
      sectionName: http
    - name: cilium-gateway
      sectionName: https
  hostnames:
    - ${gateway_hostname}
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: echo
          port: 80
