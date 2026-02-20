---
apiVersion: v1
kind: Namespace
metadata:
  name: ${velero_namespace}
---
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: velero
  namespace: kube-system
spec:
  chart: velero
  repo: https://vmware-tanzu.github.io/helm-charts
  version: "${version}"
  targetNamespace: ${velero_namespace}
  bootstrap: ${bootstrap}
  valuesContent: |-
    ${values}
