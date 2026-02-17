# Hetzner Robot Server Integration using HCCM v1.19+

This guide describes how to add Hetzner **robot servers** to a Kubernetes cluster with help of the [hcloud-cloud-controller-manager](https://github.com/hetznercloud/hcloud-cloud-controller-manager), version 1.19 or newer.
It covers configuration for both k3s and Robot nodes, including networking, configuration, and caveats. Alternatives like WireGuard exist, but are not covered here.

---

## Prerequisites for connecting a Robot node to a new or already existing Cluster

- **Hetzner vSwitch** 
    - The recommended way is using a **vSwitch**, which connects the project-level Cloud subnets to the Robot node.
    - This guide assumes the vSwitch has been created and is not currently connected to any subnet. The vSwitch can be created in the Hetzner Robot web-UI. See [Hetzner Docs](https://docs.hetzner.com/robot/dedicated-server/network/vswitch)
    - Note down the vSwitch ID and the VLAN ID. Note: vSwitch IDs are in the number range of around 10000+, while VLAN ID range is account-specific and starts from 4000 by default.
- **Webservice User** created in Hetzner Robot account settings (for API access)
    - This is required for `hccm` to list robot servers via the metadata endpoint:
        - `https://169.254.169.254/hetzner/v1/metadata/instance-id`
- `hccm` version **1.19 or newer**
- **Operating System**: Ideally use the MicroOS image created by this project. Otherwise, any Linux distribution that supports k3s will work
- **Network CNI Configuration**: 
    - Flannel: Doesn't need additional configuration.
    - Cilium: Doesn't need additional configuration, ensure `cilium_loadbalancer_acceleration_mode` is set to `"best-effort"` or `"disabled"`
    - Calico: Untested

---

## 1. Connection from Kubernetes Cluster to vSwitch

In your kube.tf-configuration:
  - Set `robot_ccm_enabled = true` and provide the Webservice User credentials in the `robot_user` and `robot_password` variables. All three are required to enable Robot server integration. If `robot_ccm_enabled` is true but credentials are not provided, the integration will not be activated.
  - Set `vswitch_id = <vswitch_id from prerequisites>`

For manual configuration of the settings, see below:

<details>
<summary>Manual configuration of HCCM-settings and vSwitch connection</summary>

### 1. HCCM-settings

- **Update the `hcloud` Kubernetes secret** with your `robot-user` and `robot-password`.
- Set `robot.enabled: true` in `hetzner_ccm_values`.
- Set the correct `cluster-cidr` (the pod subnet for your cluster).
- Deploy `hccm` version **1.19 or newer**.
- Refer to [HCCM Github if required](https://github.com/hetznercloud/hcloud-cloud-controller-manager/blob/a0217eafe74c8704a5e8086cc774ceb3de8f04e3/chart/values.yaml#L54)

### 2. Connect the Existing Cluster Subnet manually to vSwitch 

1. Choose a subnet CIDR to be used for the Robot nodes that doesn't conflict with the existing Cluster subnets, such as 10.201.0.0/16.
2. Connect the existing Cluster Cloud network to the previously created vSwitch in the web-UI and expose the routes to vSwitch. 
  - Follow the steps in [Hetzner docs](https://docs.hetzner.com/cloud/networks/connect-dedi-vswitch) on how to connect the Cluster Subnets to the vSwitch. Use your selected subnet CIDR and VLAN ID.

</details>


---

## 2. Connect the Robot to the vSwitch 

1. Follow the steps in "Step 2: Configure networking on your dedicated root servers" in [Hetzner docs](https://docs.hetzner.com/cloud/networks/connect-dedi-vswitch/#step-2-configure-networking-on-your-dedicated-root-servers) to connect the Robot node to the vSwitch.
  - Use your selected VLAN ID. 
  - If you created the Cloud->vSwitch connection via Terraform in the Step 1 of this guide, the default range for Robot is 10.201.0.0/16. The gateway is then at 10.201.0.1 and first Robot node should use private IP 10.201.0.2. 
  - Make sure to use MTU 1400 or less. Cilium is reported to be requiring MTU 1350 or less.

<details>
<summary>Robot Network configuration example for RHEL/AlmaLinux using nmcli</summary>

Assumptions (change these to your values!):
- vSwitch subnet: `10.201.0.0/16`
- VLAN ID: `4000` # "arbitrary" value, replace with your VLAN ID
- Main interface: `enp6s0`

> [!CAUTION]
> The routes and CIDR notations depend on your local setup and may vary depending on your network configuration.

```bash
nmcli connection add type vlan con-name vlan4000 ifname vlan4000 vlan.parent enp6s0 vlan.id 4000

nmcli connection modify vlan4000 802-3-ethernet.mtu 1400  # Important: vSwitch requires MTU 1400 max.
nmcli connection modify vlan4000 ipv4.addresses '10.201.0.2/16'
nmcli connection modify vlan4000 ipv4.gateway '10.201.0.1'
nmcli connection modify vlan4000 ipv4.method manual
# Route all 10.x IPs through the vSwitch gateway
nmcli connection modify vlan4000 +ipv4.routes "10.0.0.0/8 10.201.0.1"

# Apply the config
nmcli connection down vlan4000
nmcli connection up vlan4000
```

</details>

---
## 3. Verify Network connectivity
1. Log in to your Robot Node using SSH and ping one of the Cloud Control Plane nodes Private Network IP. (e.g., 10.255.0.101).
2. Log in to one of the Cloud Control Plane nodes using SSH and ping the Robot Node Private Network IP, such as 10.201.0.2.


<details>
<summary>Troubleshoot Robot Node networking</summary>

- Make sure the IP address and routing are correct on the Robot Node.
- Following examples assume Robot Node public IP 203.0.113.123, private IP 10.201.0.2, VLAN ID 4000 and device enp6s0.
- `ip route show` on the Robot Node should print similar to this:
```
default via 203.0.113.123 dev enp6s0 proto static onlink 
10.0.0.0/8 via 10.201.0.1 dev enp6s0.4000 proto static onlink 
10.201.0.0/16 dev enp6s0.4000 proto kernel scope link src 10.201.0.2 
```
- `ip addr` on the Robot Node should include similar to this:
```
2: enp6s0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    link/ether a8:a1:REDACTED brd ff:ff:ff:ff:ff:ff
    inet 203.0.113.123/32 scope global enp6s0
       valid_lft forever preferred_lft forever
    inet6 2a01:REDACTED/64 scope global 
       valid_lft forever preferred_lft forever
    inet6 fe80::REDACTED/64 scope link 
       valid_lft forever preferred_lft forever
3: enp6s0.4000@enp6s0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1400 qdisc noqueue state UP group default qlen 1000
    link/ether a8:a1:REDACTED brd ff:ff:ff:ff:ff:ff
    inet 10.201.0.2/16 brd 10.201.255.255 scope global enp6s0.4000
       valid_lft forever preferred_lft forever
    inet6 fe80::REDACTED/64 scope link 
       valid_lft forever preferred_lft forever
``` 
- You may want to try to "Refresh" the vSwitch connection in the Robot web-UIs vSwitches admin-panel. Select the vSwitch, then Robot Node and click Refresh.
- Try rebooting the Robot Node

</details>

---

## 4. Robot Node: k3s Agent Configuration

> [!IMPORTANT]
> If you set a Nodename for the k3s-agent, it must match the server name in the Hetzner Robot Web-UI.

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
      - instance.hetzner.cloud/provided-by=robot # To prevent Hetzner CSI pods from being scheduled on robot nodes
    node-taint: []
    selinux: true
    server: https://<API_SERVER_IP>:6443  # Replace with your API server IP
    token: <CLUSTER_TOKEN>                # Replace with your cluster token
    ```

---

## 5. Storage and Scheduling Notes

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

## 6. Caveats & Warnings

- This setup may not cover all edge cases (e.g., other CNIs, non-wireguard clusters, complex private networks).
- When destroying the cluster, it takes a few minutes for the vSwitch binding to be released on the Robot side.
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
