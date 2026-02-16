# Rollback Node MicroOS Manually

How to manually rollback a MicroOS node to the last snapshot or be date.

## Background

Certain versions of `linux-utils` (e.g., >2.40) may cause errors such as:

```
...cannot mount subpath... file exists... unmount...
```

For more details, refer to the [Kubernetes issue #130999](https://github.com/kubernetes/kubernetes/issues/130999).

## Step 1: Find Problematic Nodes

Run the following command to identify nodes with issues:

```bash
kubectl get pods -o wide --all-namespaces | grep CreateContainerConfigError | awk '{printf "%s%s", $8, (NR == total ? "" : ",")} {total=NR} END {print ""}'
```

**Note:** The output may include duplicates or irrelevant entries (e.g., pods with uptime of 12h).

## Step 2: Manual Rollback Per Node

SSH into each problematic node and execute the following command:

```bash
snapper --iso list | tail -2 | head -1 | awk '{print $1}' | xargs -I{} snapper rollback {} && reboot
```

### Explanation of the Command

1. `snapper --iso list`: Lists all snapshots with ISO timestamps.
2. `tail -2`: Filters the last two snapshots.
3. `head -1`: Selects the snapshot before the current one.
4. `awk '{print $1}'`: Extracts the snapshot ID.
5. `xargs -I{} snapper rollback {}`: Rolls back to the selected snapshot.
6. `&& reboot`: Reboots the node if the rollback is successful.

## Step 3: Automate Rollback with Ansible (Work in Progress)

If you have an inventory file, you can automate the rollback process using Ansible:

```bash
export COMMA_SEPARATED_NODE_LIST=$(kubectl get pods -o wide --all-namespaces | grep CreateContainerConfigError | awk '{printf "%s,", $8} END {print ""}')
echo $COMMA_SEPARATED_NODE_LIST

ansible ${COMMA_SEPARATED_NODE_LIST} -i ansible/inventory.yml \
-m shell \
-a 'snapper --iso list | tail -2 | head -1 | awk "{print $1}" | xargs -I{} snapper rollback {} && reboot'
```

## Additional Notes

### Snapshot List Example

Below is an example output of `snapper --iso list`:

```bash
   # │ Type   │ Pre # │ Date                │ User │ Used Space │ Cleanup │ Description            │ Userdata
─────┼────────┼───────┼─────────────────────┼──────┼────────────┼─────────┼────────────────────────┼──────────────
  0  │ single │       │                     │ root │            │         │ current                │
 97  │ single │       │ 2025-06-03 00:33:31 │ root │ 274.03 MiB │ number  │ Snapshot Update of #96 │ important=yes
 98  │ single │       │ 2025-06-05 00:59:06 │ root │  59.11 MiB │ number  │ Snapshot Update of #97 │ important=yes
 99  │ single │       │ 2025-06-06 01:17:29 │ root │  22.16 MiB │ number  │ Snapshot Update of #98 │ important=yes
100* │ single │       │ 2025-06-08 01:49:48 │ root │  38.02 MiB │ number  │ Snapshot Update of #99 │
```

- `*`: Marks the current/running snapshot.
- `+`: Marks the snapshot to be used on the next boot.

### Alternative: Select Snapshot by Date

To rollback to a snapshot from a specific date (e.g., June 6, 2025):

```bash
snapper --iso list | grep 06-06 | awk '{print $1}' | xargs -I{} snapper rollback {} && reboot
```
