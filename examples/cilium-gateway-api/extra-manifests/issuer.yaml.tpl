apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging-gateway
spec:
  acme:
    email: ${certificate_email}
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-staging-gateway-account-key
    solvers:
      - http01:
          gatewayHTTPRoute:
            parentRefs:
              - name: cilium-gateway
                namespace: default
                kind: Gateway
            serviceType: ClusterIP
