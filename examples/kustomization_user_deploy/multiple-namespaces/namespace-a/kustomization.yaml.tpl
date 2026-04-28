apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespace-a.yaml
  - ../base
namespace: namespace-a
