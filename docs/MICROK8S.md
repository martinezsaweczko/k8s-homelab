# MicroK8s Installation & Configuration

This guide covers the MicroK8s installation process integrated into the Ansible playbooks with proper OS configuration and best practices.

## What is MicroK8s?

MicroK8s is a lightweight, single-package Kubernetes distribution that:
- Runs on a single machine or cluster
- Uses snaps for easy installation
- Includes core Kubernetes components (CoreDNS, metrics-server, storage)
- Perfect for development, testing, and homelab setups
- Minimal resource overhead

## OS Prerequisites Applied

The `common` role automatically configures:

### 1. Disable Swap
- **Why**: Kubernetes expects swap to be disabled for proper memory management
- **Action**: Swapoff is executed and removed from `/etc/fstab`

### 2. Load Kernel Modules
```
- overlay
- br_netfilter
```
These are required for container networking and storage.

### 3. Kernel Parameters (sysctl)
```
net.bridge.bridge-nf-call-iptables: 1
net.bridge.bridge-nf-call-ip6tables: 1
net.ipv4.ip_forward: 1
vm.overcommit_memory: 1
kernel.panic: 10
kernel.panic_on_oops: 1
```

### 4. System Limits
```
nofile: 65536 (soft and hard)
nproc: 65536 (soft and hard)
```
These prevent "too many open files" errors.

### 5. Required Packages
- apt-transport-https, ca-certificates (for Helm/package managers)
- python3-pip, pyyaml, jsonpatch (for Ansible)
- openssh-server/client (for cluster communication)

## Installation Process

### Step 1: Apply Common Configuration
```bash
ansible-playbook playbooks/site.yml --tags "common" --vault-password-file .vault-pass
```

This prepares the OS with all prerequisites.

### Step 2: Install Kubernetes (Master)
```bash
ansible-playbook playbooks/kubernetes.yml --vault-password-file .vault-pass
```

This:
1. Installs MicroK8s snap
2. Waits for initialization (30 seconds)
3. Enables DNS, storage, and RBAC addons
4. Sets up kubeconfig in user home
5. Verifies cluster status

### Full Deployment
```bash
ansible-playbook playbooks/site.yml --vault-password-file .vault-pass
```

## MicroK8s Addons Enabled

### Master Nodes
- **dns** - CoreDNS for service discovery
- **storage** - Default storage class for PVCs
- **rbac** - Role-based access control

### Worker Nodes
- Minimal setup (no extra addons needed)

## Accessing the Cluster

After installation, access Kubernetes via:

```bash
# Using the kubeconfig setup by Ansible
export KUBECONFIG=$HOME/.kube/config

# Check nodes
kubectl get nodes -o wide

# Check pods
kubectl get pods --all-namespaces

# Get cluster info
kubectl cluster-info
```

## Available MicroK8s Commands

```bash
# Status
microk8s status

# Enable/disable addons
microk8s enable <addon>
microk8s disable <addon>

# List available addons
microk8s status | grep available

# Run kubectl
microk8s kubectl get nodes

# Run other tools
microk8s helm
microk8s docker
```

## MicroK8s Channels

Available installation channels:
- `stable` - Latest stable release (recommended)
- `candidate` - Release candidate
- `edge` - Latest development build
- Version-specific (e.g., `1.28/stable`)

Specify via `k8s_microk8s_channel` variable.

## Expanding to Multi-Node Cluster

When adding node02 and node03:

### 1. Get Join Token (on master node01)
```bash
microk8s add-node
# Copy the output token
```

### 2. Join Node (on worker nodes)
```bash
microk8s join <token>
```

### 3. Ansible Automation
The playbook will handle this automatically when nodes are added to inventory and roles are applied.

## Storage Configuration

By default, MicroK8s provides:
- **hostpath** storage class
- Stored in: `/var/snap/microk8s/common/default-storage`

For production Ceph integration:
1. Install Ceph (via separate playbook)
2. Configure Ceph RBD storage class
3. Configure Ceph CephFS storage class

## Common Issues & Solutions

### Issue: "microk8s: command not found"
- **Solution**: Ensure the snap is installed: `microk8s status`
- **Alternative**: Add snap bin to PATH: `export PATH=$PATH:/snap/bin`

### Issue: "Permission denied" for kubectl
- **Solution**: User added to `microk8s` group but needs re-login:
  ```bash
  newgrp microk8s
  # or logout and login again
  ```

### Issue: Cluster not ready
- **Solution**: Wait for MicroK8s to fully initialize (1-2 minutes)
  ```bash
  microk8s status --wait-ready
  ```

### Issue: Network issues between pods
- **Ensure**: DNS addon is enabled: `microk8s enable dns`

## Monitoring & Logging

### Check MicroK8s logs
```bash
# System logs
journalctl -u snap.microk8s* -n 100

# MicroK8s specific
microk8s.inspect
```

### Check Kubernetes logs
```bash
# Get pod logs
kubectl logs -n kube-system <pod-name>

# Describe resources
kubectl describe node <node-name>
kubectl describe pod -n kube-system <pod-name>
```

## Updating MicroK8s

MicroK8s updates automatically via snap, but you can trigger manually:

```bash
sudo snap refresh microk8s
```

To specify a different channel:
```bash
sudo snap refresh microk8s --channel=1.28/stable
```

## Performance Tuning

### Increase resource limits (if needed)
Edit `/etc/security/limits.conf` and increase:
```
nofile: 131072
nproc: 131072
```

### Storage optimization
Check available disk space for container images and volumes:
```bash
df -h /var/snap/microk8s/
```

## Next Steps

1. **Join additional nodes** when available (node02, node03)
2. **Install Ceph** for persistent storage
3. **Configure networking** for cross-cluster communication
4. **Deploy applications** using kubectl or Helm
5. **Monitor** cluster health and performance

## References

- [MicroK8s Official Docs](https://microk8s.io/docs)
- [Kubernetes Best Practices](https://kubernetes.io/docs/concepts/)
- [MicroK8s Addons](https://microk8s.io/docs/addons)
