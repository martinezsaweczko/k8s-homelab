# Ceph CSI RBD Integration with Kubernetes

This Ansible role (`k8s-ceph-csi`) automates the installation and configuration of Ceph CSI RBD driver for Kubernetes persistent storage.

## What It Does

The role automates the following steps:

1. **Validates Environment**
   - Checks for kubeconfig file existence
   - Verifies Kubernetes cluster access

2. **Prepares Ceph Configuration**
   - Retrieves Ceph cluster FSID
   - Gets monitor addresses
   - Retrieves client.kubernetes key

3. **Sets Up Kubernetes**
   - Creates `ceph-csi-rbd` namespace
   - Creates Ceph secrets in both namespaces with:
     - Ceph client credentials
     - Monitor configuration (ceph.conf)

4. **Installs CSI RBD Driver**
   - Adds ceph-csi Helm repository
   - Installs ceph-csi-rbd chart
   - Waits for provisioner to be ready

5. **Creates StorageClass**
   - Configures `ceph-csi-rbd` StorageClass
   - Points to Ceph cluster and kubernetes pool
   - Configures reclaim policy and volume expansion

6. **Optional Testing**
   - Creates test PVC (1Gi)
   - Creates test Pod with volume mount
   - Writes/reads test file to Ceph storage

## Usage

### Standalone Installation

```bash
ansible-playbook playbooks/k8s-ceph-csi.yml
```

### Full Setup (with Ceph and K8s)

```bash
ansible-playbook playbooks/site.yml
```

### Enable Testing

Edit `playbooks/k8s-ceph-csi.yml` or run with override:

```bash
ansible-playbook playbooks/k8s-ceph-csi.yml -e "enable_ceph_csi_test=true"
```

## Configuration Variables

Default values in `roles/k8s-ceph-csi/defaults/main.yml`:

| Variable                 | Default                  | Description                             |
|--------------------------|--------------------------|-----------------------------------------|
| `ceph_csi_namespace`     | ceph-csi-rbd             | CSI driver namespace                    |
| `ceph_csi_rbd_version`   | v3.15.1                  | CSI RBD version                         |
| `ceph_k8s_namespace`     | default                  | Kubernetes namespace for test resources |
| `ceph_k8s_pool`          | kubernetes               | Ceph RBD pool                           |
| `ceph_k8s_client`        | kubernetes               | Ceph client user                        |
| `kubeconfig_path`        | /home/david/.kube/config | Path to kubeconfig                      |
| `ceph_csi_storage_class` | ceph-csi-rbd             | StorageClass name                       |
| `enable_ceph_csi_test`   | false                    | Run integration test                    |
| `ceph_csi_test_pvc_size` | 1Gi                      | Test PVC size                           |

## Verification

After installation, verify the setup:

```bash
# Check CSI RBD pods
kubectl get pods -n ceph-csi-rbd

# Check StorageClass
kubectl get storageclass ceph-csi-rbd

# Create a test PVC
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ceph-csi-rbd
  resources:
    requests:
      storage: 1Gi
EOF

# Check PVC status
kubectl get pvc test-pvc

# List Ceph RBD images
sudo rbd ls -p kubernetes --format json
```

## Troubleshooting

### PVC Stuck in Pending

Check provisioner logs:
```bash
kubectl logs -n ceph-csi-rbd -l app=ceph-csi-rbd-provisioner
```

Check secrets exist in both namespaces:
```bash
kubectl get secret ceph-secret -n ceph-csi-rbd
kubectl get secret ceph-secret -n default
```

### Monitor Configuration Issues

Verify the ceph.conf in the secret:
```bash
kubectl get secret ceph-secret -n ceph-csi-rbd -o jsonpath='{.data.ceph\.conf}' | base64 -d
```

Should contain:
```
[global]
fsid = <cluster-id>
mon_host = <monitor-addresses>
```

## Files Created

```
roles/k8s-ceph-csi/
├── defaults/
│   └── main.yml           # Configuration variables
├── tasks/
│   ├── main.yml           # Main installation tasks
│   └── test.yml           # Optional integration tests
└── README.md              # This file

playbooks/
└── k8s-ceph-csi.yml       # Playbook to run the role
```

## Next Steps

1. Run the playbook to install CSI RBD
2. Create StorageClasses for different use cases
3. Deploy applications using Ceph persistent storage
4. Monitor Ceph pool usage and RBD image creation

## References

- [Ceph CSI RBD Documentation](https://docs.ceph.com/en/quincy/rbd/rbd-kubernetes/)
- [Kubernetes Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [Ceph RBD StorageClass](https://github.com/ceph/ceph-csi/tree/master/examples/rbd)
