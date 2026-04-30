apiVersion: v1
kind: Pod
metadata:
  name: demo
spec:
  containers:
    - name: demo-container
      image: registry.k8s.io/busybox
      command: [ "/bin/sh", "-c", "env" ]
      env:
        - name: DEMO_ENVIRONMENT_VARIABLE
          valueFrom:
            configMapKeyRef:
              name: demo-config
              key: someConfigKey
  restartPolicy: Never
