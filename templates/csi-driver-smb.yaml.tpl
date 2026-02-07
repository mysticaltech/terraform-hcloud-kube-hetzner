---
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: csi-driver-smb
  namespace: kube-system
spec:
  chart: csi-driver-smb
  repo: https://raw.githubusercontent.com/kubernetes-csi/csi-driver-smb/master/charts
  version: "${version}"
  targetNamespace: kube-system
  bootstrap: ${bootstrap}
  valuesContent: |-
    ${values}
