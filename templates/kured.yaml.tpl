---
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: kured
  namespace: kube-system
spec:
  chart: kured
  repo: https://kubereboot.github.io/charts
  version: "${version}"
  targetNamespace: kube-system
  bootstrap: false
  valuesContent: |-
    ${values}
