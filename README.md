# K8s Homelab - Kubernetes & Ceph Ansible Automation

Automated installation and configuration of Kubernetes and Ceph clusters using Ansible with GitHub Secrets integration for secure credential management.

**Supports**: Fedora 38+, Ubuntu 20.04 LTS+, RHEL 8+

## Quick Start

1. **Clone the repository and configure inventory:**
   ```bash
   cp inventories/hosts.example.yml inventories/hosts.yml
   # Edit with your target hosts
   ```

2. **Set up Ansible vault for secrets:**
   ```bash
   ansible-vault create group_vars/all/vault.yml
   # Add your sensitive data (passwords, keys, etc.)
   ```

3. **Run the main playbook:**
   ```bash
   ansible-playbook playbooks/site.yml --vault-password-file .vault-pass
   ```

## Features

- ✅ Modular role-based architecture
- ✅ GitHub Secrets integration for secure credential management
- ✅ Separate Kubernetes and Ceph installation playbooks
- ✅ Environment-specific variables (group_vars, host_vars)
- ✅ **Multi-OS support**: Fedora, Ubuntu, RHEL
- ✅ CI/CD ready with GitHub Actions workflow

## Documentation

See [SETUP.md](SETUP.md) for detailed setup and usage instructions.

## Directory Structure

- **playbooks/** - Main orchestration playbooks
- **roles/** - Reusable Ansible roles for different components
- **inventories/** - Host inventory configurations
- **group_vars/** - Group-level variables
- **host_vars/** - Host-specific variables

## GitHub Secrets Setup

For CI/CD pipelines, add these secrets in GitHub:

- `VAULT_PASSWORD` - Ansible vault password for encrypted variables
- `SSH_PRIVATE_KEY` - (Optional) SSH key for automation

See SETUP.md for detailed instructions.

## Requirements

- Ansible 2.9+
- Python 3.7+
- SSH access to target hosts
- **Fedora 38+, Ubuntu 20.04 LTS+, or RHEL 8+ on target hosts**

## Running the playbooks (as executed on this cluster)

The `.env` file at the repo root holds the SSH credentials (`ssh_user`, `ssh_password`).
They are **not** read automatically by Ansible; they are passed as extra vars.
All commands run from the repo root and use the virtualenv in `.venv/`.

> One playbook run covers **all** servers at once: the inventory groups
> (`k8s_masters`, `ceph_monitors`, `ceph_osds`) map to the 3 nodes
> (k8s1/k8s2/k8s3.martinez-saweczko.es). Use `--limit` to target a single server.

```bash
cd /home/david/Externo/k8s-homelab
source .env   # loads ssh_user / ssh_password

# 1) Full installation on all 3 servers (bootstrap + common + MicroK8s + Ceph + CSI)
.venv/bin/ansible-playbook playbooks/site.yml \
  --vault-password-file .vault-pass \
  -e ansible_user=$ssh_user -e ansible_password=$ssh_password

# 2) (If needed) re-run only the Ceph OSD creation on all OSD nodes
.venv/bin/ansible-playbook playbooks/ceph.yml --tags ceph-osd \
  --vault-password-file .vault-pass \
  -e ansible_user=$ssh_user -e ansible_password=$ssh_password

# 3) (If needed) re-run the Ceph CSI setup including the end-to-end PVC test
.venv/bin/ansible-playbook playbooks/k8s-ceph-csi.yml \
  -e enable_ceph_csi_test=true \
  --vault-password-file .vault-pass \
  -e ansible_user=$ssh_user -e ansible_password=$ssh_password
```

Useful variations:

```bash
# Run on a single server only (inventory names: homelab1, homelab2, homelab3)
.venv/bin/ansible-playbook playbooks/site.yml --limit homelab2 \
  --vault-password-file .vault-pass \
  -e ansible_user=$ssh_user -e ansible_password=$ssh_password

# Check SSH connectivity to all nodes
.venv/bin/ansible all -m ping \
  --vault-password-file .vault-pass \
  -e ansible_user=$ssh_user -e ansible_password=$ssh_password

# Dry-run / syntax check
.venv/bin/ansible-playbook playbooks/site.yml --syntax-check \
  --vault-password-file .vault-pass
```

## Kubernetes administration & troubleshooting

All commands run on any of the 3 nodes as `root` (e.g. `ssh root@k8s1.martinez-saweczko.es`).
This cluster uses **MicroK8s**, so `kubectl` is a wrapper for `microk8s.kubectl`.

```bash
# Cluster / node status
microk8s status                       # MicroK8s + HA status (dqlite masters)
microk8s kubectl get nodes -o wide    # node list, IPs, versions
kubectl get nodes                     # same via the kubectl wrapper

# Workloads
kubectl get pods -A -o wide           # all pods on all namespaces
kubectl get sc                        # storage classes (ceph-csi-rbd, microk8s-hostpath)
kubectl get pvc -A                    # persistent volume claims
kubectl describe pod <pod> -n <ns>    # events (why is my pod pending?)
kubectl logs <pod> -n <ns> [-c <container>]

# Ceph CSI driver
kubectl get pods -n ceph-csi-rbd -o wide   # provisioner + nodeplugin pods
kubectl logs -n ceph-csi-rbd deploy/ceph-csi-rbd-provisioner -c csi-rbdplugin --tail=50

# Services / daemons (MicroK8s runs as snap services)
microk8s stop && microk8s start       # restart MicroK8s on one node (do it node by node!)
journalctl -u snap.microk8s.daemon-kubelite -f   # control-plane logs
microk8s inspect                      # full diagnostics report

# Kubeconfig for remote kubectl access
microk8s config                       # prints kubeconfig (also in ~/.kube/config)
```

**Note:** on multi-NIC nodes the kubelet IP is pinned via `--node-ip=` in
`/var/snap/microk8s/current/args/kubelet` and Calico autodetection via
`can-reach=` in `/var/snap/microk8s/current/args/cni-network/cni.yaml`.
Restart MicroK8s after changing them.

## Ceph administration & troubleshooting

Run on any node as `root` (the `ceph` CLI authenticates with
`/etc/ceph/ceph.client.admin.keyring` automatically).

```bash
# Overall health
ceph -s                               # cluster status summary
ceph health detail                    # details on any HEALTH_WARN
ceph df                               # capacity usage per pool

# Monitors / managers
ceph mon stat                         # monitor quorum status
ceph mon dump                         # monitor map (addresses)
ceph mgr stat                         # active/standby managers
ceph mgr module ls                    # enabled mgr modules

# OSDs
ceph osd tree                         # OSDs per host, up/in state, class, weight
ceph osd df                           # per-OSD usage
ceph-volume lvm list                  # OSDs on the local node (LVM layout)
systemctl status ceph-osd@0           # OSD daemon state (id from ceph-volume lvm list)
journalctl -u ceph-osd@0 -f           # OSD logs

# Pools / RBD
ceph osd pool ls detail               # pools (kubernetes pool: size 3, min_size 2)
rbd ls kubernetes                     # RBD images in the kubernetes pool (one per PVC)
rbd du kubernetes                     # space used by images

# Services
systemctl status ceph-mon@$(hostname -s)   # monitor daemon
systemctl status ceph-mgr@$(hostname -s)   # manager daemon

# Crash log (Fedora's mgr build logs module-scan crashes on every mgr restart;
# they are harmless noise - archive them to get back to HEALTH_OK)
ceph crash ls-new                     # unarchived crashes
ceph crash info <id>                  # crash details
ceph crash archive-all                # clear them all
```

## Ceph credentials & dashboard access

| What | Where / Value |
|------|---------------|
| **Ceph Dashboard URL** | `http://172.26.20.248:8080` (works on any monitor IP: .246/.247/.248, HTTP no SSL, HA via standby mgrs) |
| **Dashboard user** | `admin` |
| **Dashboard password** | Value of `ceph_dashboard_password` — default `Test123!` in `roles/ceph-monitor/defaults/main.yml` |
| **Ceph CLI admin key** | `/etc/ceph/ceph.client.admin.keyring` on each server (used transparently by `ceph`/`rbd` as root) |
| **Kubernetes RBD client** | Ceph user `client.kubernetes`, keyring at `/etc/ceph/ceph.client.kubernetes.keyring`; also stored in the `ceph-secret` k8s Secrets (namespaces `ceph-csi-rbd` and `default`) used by the CSI driver |
| **Cluster FSID** | `ceph fsid` on any node (also in `/etc/ceph/ceph.conf`) |

Change the dashboard password:

```bash
echo -n 'NewSecurePassword' > /tmp/pwd.txt
ceph dashboard ac-user-set-password admin -i /tmp/pwd.txt
rm -f /tmp/pwd.txt
```

## License

See LICENSE file


*For testing with 1 OSD*

 ceph osd pool set kubernetes size 1
Error EPERM: configuring pool size as 1 is disabled by default.
ceph config set global mon_allow_pool_size_one true
ceph osd pool set kubernetes size 1
Error EPERM: WARNING: setting pool size 1 could lead to data loss without recovery. If you are *ABSOLUTELY CERTAIN* that is what you want, pass the flag --yes-i-really-mean-it.
ceph osd pool set kubernetes size 1 --yes-i-really-mean-it
