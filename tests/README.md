# Hetzner Test Presets

These `.tfvars` files are used by `.github/workflows/hetzner-test.yaml` to run a
matrix of real deployment tests.

- `default.tfvars`: baseline defaults
- `nginx_ingress.tfvars`: deploy with NGINX ingress controller
- `rke2.tfvars`: deploy with RKE2 distribution
