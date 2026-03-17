---
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: csi-driver-nfs
  namespace: kube-system
spec:
  chart: csi-driver-nfs
  repo: https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
  version: "${version}"
  targetNamespace: kube-system
  bootstrap: ${bootstrap}
  valuesContent: |-
    ${values}
