---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: kured
  namespace: kube-system
spec:
  selector:
    matchLabels:
      name: kured
  template:
    metadata:
      labels:
        name: kured
    spec:
      serviceAccountName: kured
      containers:
        - name: kured
          command:
            - /usr/bin/kured
            %{~ for key, value in options ~}
            - --${key}=${value}
            %{~ endfor ~}
