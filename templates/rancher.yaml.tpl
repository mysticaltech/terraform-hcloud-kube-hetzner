---
apiVersion: v1
kind: Namespace
metadata:
  name: cattle-system
---
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: rancher
  namespace: kube-system
spec:
  chart: rancher
  repo: https://releases.rancher.com/server-charts/${rancher_install_channel}
  version: "${version}"
  targetNamespace: cattle-system
  bootstrap: ${bootstrap}
  valuesContent: |-
    ${values}
