apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - issuer.yaml
  - echo.yaml
  - gateway.yaml
  - http-route.yaml
