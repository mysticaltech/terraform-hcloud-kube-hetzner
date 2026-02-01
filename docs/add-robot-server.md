# Hetzner Robot Server Integration using HCCM v1.19+

This guide describes how to add Hetzner **robot servers** to a Kubernetes cluster with help of the [hcloud-cloud-controller-manager](https://github.com/hetznercloud/hcloud-cloud-controller-manager), version 1.19 or newer.
It covers configuration for both k3s and Robot nodes, including networking, configuration, and caveats.

---

## Prerequisites

- **vSwitch** set up for private networking between Cloud and Robot nodes
- **Webservice User** created in Hetzner Robot account settings (for API access)
- `hccm` version **1.19 or newer**
- **Operating System**: Ideally use the MicroOS image created by this project. Otherwise, any Linux distribution that supports k3s will work

---

## 1. Networking: Private Communication

- **Robot and Cloud servers communication happens over a private network.**
    - The recommended way is using a **vSwitch**.
    - Alternatives like WireGuard exist, but are not covered here.
    - Ensure all nodes can reach each other via internal IPs (e.g., `10.x.x.x`).

---

## 2. Hetzner Robot API Access

- Create a **Webservice User** in your Hetzner Robot account.
- This is required for `hccm` to list robot servers via the metadata endpoint:
    - `https://169.254.169.254/hetzner/v1/metadata/instance-id`

---

## 3. Robot Node Network Configuration

- **Manually configure** the network interface and routes on the robot server.
- For Ubuntu, see [Hetzner docs](https://docs.hetzner.com/cloud/networks/connect-dedi-vswitch#persistent-example-configurations).
- For RHEL-based systems (e.g., AlmaLinux), use the following `nmcli` commands:

<details>
<summary>RHEL/AlmaLinux nmcli Example</summary>

Assumptions (change these to your values!):
- vSwitch subnet: `10.1.0.0/24`
- vSwitch ID: `9999` # arbitrary value, replace with your vSwitch ID
- Main interface: `enp6s0`

> [!CAUTION]
> The routes and CIDR notations depend on your local setup and may vary depending on your network configuration.

```bash
nmcli connection add type vlan con-name vlan9999 ifname vlan9999 vlan.parent enp6s0 vlan.id 9999

nmcli connection modify vlan9999 802-3-ethernet.mtu 1400  # Important: vSwitch requires MTU 1400
nmcli connection modify vlan9999 ipv4.addresses '10.1.0.2/24'
nmcli connection modify vlan9999 ipv4.gateway '10.1.0.1'
nmcli connection modify vlan9999 ipv4.method manual
# Route all 10.x IPs through the vSwitch gateway
nmcli connection modify vlan9999 +ipv4.routes "10.0.0.0/8 10.1.0.1"

# Apply the config
nmcli connection down vlan9999
nmcli connection up vlan9999
```

</details>

---

## 4. HCCM Helm Chart Configuration

- **Update the `hcloud` Kubernetes secret** with your `robot-user` and `robot-password`.
- Set `networking.enabled: true` in `hetzner_ccm_values`.
- Set the correct `cluster-cidr` (the pod subnet for your cluster).
- Deploy `hccm` version **1.19 or newer**.

Example `hetzner_ccm_values` for Helm:

```yaml
networking:
  enabled: true
robot:
  enabled: true

args:
  allocate-node-cidrs: "true"
  cluster-cidr: "10.42.0.0/16" # Adjust to your pod subnet

env:
  HCLOUD_LOAD_BALANCERS_ENABLED:
    value: "true"
  HCLOUD_LOAD_BALANCERS_LOCATION:
    value: "nbg1"  # Adjust to your LB region
  HCLOUD_LOAD_BALANCERS_USE_PRIVATE_IP:
    value: "true"
  HCLOUD_LOAD_BALANCERS_DISABLE_PRIVATE_INGRESS:
    value: "true"
  HCLOUD_NETWORK_ROUTES_ENABLED:
    value: "false"

  HCLOUD_TOKEN:
    valueFrom:
      secretKeyRef:
        name: hcloud
        key: token

  ROBOT_USER:
    valueFrom:
      secretKeyRef:
        name: hcloud
        key: robot-user
        optional: true
  ROBOT_PASSWORD:
    valueFrom:
      secretKeyRef:
        name: hcloud
        key: robot-password
        optional: true
```

---

## 5. Robot Node: k3s Agent Configuration

1. **Create `/etc/rancher/k3s/config.yaml`** on the robot node:

    ```yaml
    flannel-iface: enp6s0  # Set to your main interface (only needed for Flannel CNI)
    prefer-bundled-bin: true
    kubelet-arg:
      - cloud-provider=external
      - volume-plugin-dir=/var/lib/kubelet/volumeplugins
      - kube-reserved=cpu=50m,memory=300Mi,ephemeral-storage=1Gi
      - system-reserved=cpu=250m,memory=6000Mi  # Optional: reserve some space for system
    node-label:
      - k3s_upgrade=true
    node-taint: []
    selinux: true
    server: https://<API_SERVER_IP>:6443  # Replace with your API server IP
    token: <CLUSTER_TOKEN>                # Replace with your cluster token
    ```

2. **Before starting the agent**, verify network connectivity:
    - You must be able to `ping` other nodes' internal IPs (e.g., `ping 10.255.0.101`).

---

## 6. Storage and Scheduling Notes

- **Hetzner Cloud Volumes** do **not** work on robot servers (CSI driver limitation).
    - Use [Longhorn](https://longhorn.io/) or other external storage.
    - Pods using cloud volumes cannot be scheduled on robot nodes.
- **Longhorn**: Install `open-iscsi` and start the service:
    ```bash
    sudo dnf install -y iscsi-initiator-utils
    sudo systemctl start iscsid
    ```
- **Node Scheduling**:
    - Use taints and labels to control pod placement.
    - To prevent Hetzner CSI pods from being scheduled on robot nodes, apply the label:
        ```
        instance.hetzner.cloud/provided-by=robot
        ```
      [Reference](https://github.com/hetznercloud/csi-driver/blob/main/docs/kubernetes/README.md#integration-with-root-servers)

---

## 7. Caveats & Warnings

- This setup may not cover all edge cases (e.g., other CNIs, non-wireguard clusters, complex private networks).
- **Test your network thoroughly** before adding robot nodes to production clusters.
- **MTU Issues**: When using vSwitch, MTU configuration is critical:
  - vSwitch has a maximum MTU of 1400
  - Some users report needing even lower MTU values (e.g., 1350 or less) for stable operation
  - This particularly affects Cilium CNI users
  - Without proper MTU configuration, you may experience:
    - Pods unable to connect to the Kubernetes API
    - Network instability for pods not using host networking
    - Intermittent connection issues
  - Test different MTU values if you encounter network issues

---

## References

- [Hetzner Cloud Controller Manager](https://github.com/hetznercloud/hcloud-cloud-controller-manager)
- [Hetzner vSwitch & Robot Networking](https://docs.hetzner.com/cloud/networks/connect-dedi-vswitch)
- [Hetzner CSI Driver: Root Server Integration](https://github.com/hetznercloud/csi-driver/blob/main/docs/kubernetes/README.md#integration-with-root-servers)
