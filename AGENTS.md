# AGENTS.md - Kube-Hetzner Terraform Module

## Build/Lint/Test Commands

### Formatting & Validation
- `terraform fmt` - Format all Terraform files
- `terraform fmt --check` - Check formatting without modifying files
- `terraform validate` - Validate Terraform configuration syntax and structure

### Planning & Testing
- `terraform plan` - Generate and show execution plan (always run before apply)
- `terraform apply` - Apply changes
- `terraform init -upgrade` - Initialize and upgrade providers to latest versions

### Single Test Execution
- Run `terraform plan` in test directory for isolated testing
- Use `terraform workspace select <name>` for environment-specific testing

### Security & Linting
- `tfsec --ignore-hcl-errors` - Scan for security issues in Terraform code

## Architecture & Codebase Structure

### Core Components
- **main.tf**: Core Hetzner Cloud infrastructure (networks, subnets, firewalls, SSH keys)
- **control_planes.tf**: Control plane node pool management
- **agents.tf**: Agent/worker node pool management
- **autoscaler-agents.tf**: Kubernetes autoscaler configuration
- **locals.tf**: Business logic, computed values, network calculations (CRITICAL file)
- **variables.tf**: All configurable parameters and defaults
- **versions.tf**: Terraform and provider version constraints

### Key Subprojects/Modules
- **modules/**: Reusable Terraform modules
- **examples/**: Usage examples and configurations
- **templates/**: Cloud-init and k3s configuration templates
- **kustomize/**: Kubernetes resource customization
- **packer-template/**: MicroOS snapshot creation

### Internal APIs & Patterns
- **Network Architecture**: Private Hetzner networks with calculated subnets
- **Node Pools**: Dynamic creation of control plane and agent node pools
- **Load Balancing**: Hetzner LB integration with ingress controllers
- **CNI Options**: Flannel, Calico, Cilium support
- **CSI Integration**: Hetzner CSI driver for persistent volumes

## Code Style Guidelines

### Terraform/HCL Conventions
- **Formatting**: Always run `terraform fmt` before commits
- **Naming**: snake_case for variables and locals, resource names descriptive
- **Structure**: Group related resources, use locals for complex expressions
- **Comments**: Document complex logic, especially in locals.tf

### Imports & Dependencies
- Group imports by type (Hetzner, Kubernetes, utilities)
- Use explicit provider versions in versions.tf
- Avoid unnecessary provider dependencies

### Error Handling & Validation
- Use variable validation blocks for input constraints
- Handle optional resources with count expressions
- Validate network calculations to prevent conflicts

### Types & Structure
- Use appropriate Terraform types (string, number, bool, list, map, object)
- Leverage locals for computed values to avoid repetition
- Structure complex variables as objects with clear schemas

## CLAUDE.md Integration

This codebase follows the comprehensive guidelines in CLAUDE.md:

- **Security First**: Scrutinize all issues/PRs for malicious intent
- **Git Workflow**: Always `git pull origin master` before work
- **Testing**: Validate with `terraform plan` before applying
- **Documentation**: Update docs when code changes
- **Backward Compatibility**: Never break existing deployments
- **External Tools**: Use Gemini CLI for large context, Codex CLI for hard reasoning

## Critical Files to Understand

1. **locals.tf**: Contains all business logic and network calculations
2. **variables.tf**: Complete configuration reference
3. **versions.tf**: Provider and version context
4. **main.tf**: Core infrastructure provisioning logic
