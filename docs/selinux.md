# SELinux policy provenance and troubleshooting

kube-hetzner keeps SELinux enforcing by default on openSUSE Leap Micro and
MicroOS nodes. That is intentional: these are immutable-style Kubernetes hosts,
so SELinux is another defense-in-depth boundary around host files, host
processes, capabilities, type transitions, and container access to labeled
paths.

The shipped policy is not a generic "allow containers everything" profile. It
relaxes specific denials that were hit by real kube-hetzner workloads over the
v2 lifetime, plus a small v3 Leap Micro policy for metrics, exporters, port
binds, and probe traffic. The broadest deliberate relaxation is allowing
containers to bind/connect to unreserved TCP ports in the Leap Micro policy:
Kubernetes workloads and hostNetwork pods commonly choose arbitrary high ports,
so the module favors a working cluster baseline and expects workload-specific
tightening to happen with targeted local policies when needed.

## Policy files

- `templates/kube-hetzner-selinux.te` (`kube_hetzner_selinux`) is the v2
  heritage policy. It was inline in `locals.tf` until `bf19aef` extracted it
  without functional changes. Most rules predate extraction and were added as
  workload denials appeared.
- `templates/k8s-custom-policies.te` (`k8s_custom_policies`) was added in v3
  by `4346724` for Leap Micro/RKE2 coverage. It is intentionally smaller and
  focused on metrics-server, node-exporter, port binds, and readiness/liveness
  traffic.
- There is small deliberate overlap: both policies allow certificate reads, and
  both now allow `container_t` read/write access to `kernel_t:tcp_socket` for
  probe traffic. Keeping the overlap near release is lower risk than merging
  the templates and accidentally changing rendered user data.

## Provenance

| Rule group | Purpose | Origin |
| --- | --- | --- |
| `iscsid_t` execute/socket rules | Let iSCSI start for Longhorn and similar storage. | `4f93c2c` created textual iSCSI policy for Longhorn; `b56fe47` folded it into `kube_hetzner_selinux`; origin: pre-extraction accretion. |
| `iscsid_t self:capability dac_override` | Longhorn iSCSI/RKE2 compatibility. | `3285c91` added it with a Longhorn issue reference (`longhorn/longhorn#5627` comment URL); `4346724` carried it into the extracted template. |
| `kernel_generic_helper_t` | Permit kernel helper execution/key access seen on MicroOS hosts. | `729113d`; origin: pre-extraction accretion, purpose inferred from target domain and rules. |
| `init_t`, `systemd_logind_t`, `systemd_hostnamed_t` unlabeled/search rules | Allow bootstrap/systemd processes to handle unlabeled paths produced during node setup and relabeling. | `b56fe47` introduced init unlabeled operations; `604d165` added logind/hostnamed searches; `554dd1e` normalized the final set. |
| `container_t` reads of `cert_t` | Let system-upgrade-controller and cluster-autoscaler read certificates. | `604d165` commit message: "allow system upgrade controller and cluster autoscaler to read certificates". |
| `container_var_lib_t` and `var_lib_t` files/dirs | Support containers and DaemonSets using hostPath-style state under `/var/lib`. | `729113d` introduced container var-lib file writes; `be22b9d` added dir RW for DaemonSets with hostPath volumes; `21a930f` synced file permissions and added `append`; `f582c89` added `container_var_lib_t:sock_file write` for JuiceFS from issue `#697`. |
| `etc_t` dirs/files/sockets | Support CSI/CNI workloads that manage sockets or generated files under `/etc`. | `4e6d3fe` for Vault CSI daemonset sockets; `1ad4e95` for Linkerd CNI file/watch behavior. |
| `usr_t`, `container_file_t`, `container_share_t`, `container_runtime_exec_t`, `container_runtime_t` | Permit observed container runtime, shared path, and executable access patterns. | `729113d` and `33e67b5`; origin: pre-extraction accretion, purpose inferred from labels and permissions. |
| `container_log_t`, `var_log_t` | Permit log readers/writers such as Fluent Bit. | `8c92f39` introduced log/proc additions; `fb51135` explicitly adjusted policy for Fluent Bit; `554dd1e` normalized the final set. |
| `kernel_t:system module_request`, `proc_t:filesystem associate` | Permit observed module/proc interactions from containerized system components. | `8c92f39`; origin: pre-extraction accretion, purpose inferred from rule names. |
| `self:bpf map_create` | Cilium BPF map creation. | `7cdb43a` "fixed cilium selinux issues". |
| `self:io_uring sqpoll` and `io_uring_t:anon_inode` | Allow container workloads that use io_uring anonymous inodes. | `123377d` added the initial io_uring rules; `ff05af8` and `2d75628` expanded/fixed the anon-inode permissions. |
| `init_t container_file_t`, `fuse_device_t`, `http_port_t` | Support observed FUSE-backed storage and init/bootstrap access patterns. | `ff05af8`; origin: pre-extraction accretion, purpose inferred from targets. |
| `container_var_run_t` | Allow container run-state file updates. | `2d75628` "fix SELinux module not applying"; purpose inferred from target label. |
| `fixed_disk_device_t` and `removable_device_t` block `getattr` | SigNoz host metrics over block devices. | `f582c89`, reported in issue `#697`. |
| `container_t kernel_t:tcp_socket { read write }` | Let CSI liveness/readiness probes talk to kernel-labeled sockets instead of crash-looping. | `62426d9` / PR `#2229`, fixes issue `#2203`; backported from the v3 Leap Micro policy. |
| Leap Micro `cert_t`, `proc_t`, `sysfs_t`, `security_t`, `init_t` reads | Metrics-server and node-exporter host metric collection. | `4346724` added `k8s_custom_policies`; purposes are documented in the file comments. |
| Leap Micro port, node, peer, and container TCP rules | Metrics/exporter binds, arbitrary Kubernetes workload high-port binds, and readiness/liveness traffic. | `4346724` added `k8s_custom_policies`; purposes are documented in the file comments. |

## Fixing a denied workload the right way

1. Check actual AVC denials on the affected node:

   ```sh
   ausearch -m avc -ts boot
   journalctl -b | grep -i 'avc:  denied'
   ```

2. Prefer a targeted local policy for the workload. The packer images include
   `udica` for this flow:

   ```sh
   # Find container
   crictl ps

   # Generate inspection
   crictl inspect <container-id> > container.json

   # Create profile
   udica -j container.json myapp --full-network-access

   # Install module
   semodule -i myapp.cil /usr/share/udica/templates/{base_container.cil,net_container.cil}
   ```

   Then set the workload's SELinux type:

   ```yaml
   apiVersion: apps/v1
   kind: Deployment
   spec:
     template:
       spec:
         containers:
           - name: my-container
             securityContext:
               seLinuxOptions:
                 type: myapp.process
   ```

3. Use `selinux = false` on only the affected nodepool as the last resort. The
   global `enable_selinux = false` switch exists, but disabling enforcement
   cluster-wide removes the immutable-OS defense-in-depth baseline.

4. To propose a kube-hetzner rule upstream, include the AVC lines, workload
   name/version, Kubernetes distribution (`k3s` or `rke2`), OS image
   (`leapmicro` or `microos`), and whether a targeted `udica` policy solved it.
   Rules without real AVC evidence should stay local.
