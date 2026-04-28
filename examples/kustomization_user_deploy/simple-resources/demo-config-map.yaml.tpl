apiVersion: v1
kind: ConfigMap
metadata:
  name: demo-config
data:
  someConfigKey: ${my_config_key}
