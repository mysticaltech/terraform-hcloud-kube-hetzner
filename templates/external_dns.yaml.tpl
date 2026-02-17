---
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: external-dns
  namespace: kube-system
spec:
  chart: external-dns
  repo: https://kubernetes-sigs.github.io/external-dns/
  version: "${version}"
  targetNamespace: kube-system
  bootstrap: ${bootstrap}
  valuesContent: |-
    ${values}
