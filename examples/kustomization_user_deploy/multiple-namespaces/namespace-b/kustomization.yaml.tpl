apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespace-b.yaml
  - ../base
namespace: namespace-b
