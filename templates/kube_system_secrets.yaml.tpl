%{ for secret_name, secret_values in kube_system_secrets ~}
apiVersion: v1
kind: Secret
metadata:
  name: ${secret_name}
  namespace: kube-system
type: Opaque
data:
%{ for secret_key, secret_value in secret_values ~}
  ${secret_key}: ${base64encode(secret_value)}
%{ endfor ~}
---
%{ endfor ~}
