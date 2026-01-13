# Ceph + MicroK8s Integration

This guide covers integrating Ceph storage with MicroK8s for persistent volume claims (PVCs).

## Architecture Overview

```
┌─────────────────────────────────────────┐
│        MicroK8s Kubernetes Cluster      │
│  ┌──────────────┬──────────────────┐   │
│  │ StorageClass │ StorageClass     │   │
│  │  ceph-rbd    │  ceph-cephfs     │   │
│  └──────┬───────┴────────┬─────────┘   │
│         │                │              │
└─────────┼────────────────┼──────────────┘
          │                │
      RBD Pool          CephFS
     (Block Storage)    (File Storage)
          │                │
          └────────┬───────┘
                   │
         ┌─────────▼──────────┐
         │  Ceph Cluster      │
         │ ┌─────┬─────┬─────┐│
         │ │MON 1│MON 2│MON 3││
         │ └─────┴─────┴─────┘│
         │ ┌─────┬─────┬─────┐│
         │ │OSD 1│OSD 2│OSD 3││
         │ └─────┴─────┴─────┘│
         └────────────────────┘
```

## Storage Classes

### 1. Ceph RBD (Block Storage)
- **StorageClass**: `ceph-rbd`
- **Access Mode**: ReadWriteOnce (RWO)
- **Use Case**: Databases, stateful applications
- **Pool**: `kubernetes`
- **Format**: ext4

Example:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-db-storage
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ceph-rbd
  resources:
    requests:
      storage: 10Gi
```

### 2. CephFS (File Storage)
- **StorageClass**: `ceph-cephfs`
- **Access Mode**: ReadWriteMany (RWX)
- **Use Case**: Shared file storage, multi-pod access
- **Format**: CephFS (POSIX-compliant)

Example:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: shared-storage
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ceph-cephfs
  resources:
    requests:
      storage: 50Gi
```

## Installation Steps

### 1. Deploy Ceph Cluster
```bash
# Deploy Ceph monitors and OSDs
ansible-playbook playbooks/ceph.yml --vault-password-file .vault-pass
```

This:
1. Installs Ceph packages
2. Creates and initializes monitors
3. Configures OSDs
4. Creates RBD pool for Kubernetes
5. Integrates with MicroK8s
6. Creates StorageClasses

### 2. Verify Ceph Cluster Health
```bash
# SSH into a Ceph monitor node
ssh -i your-key node01

# Check cluster status
ceph -s

# Check OSD status
ceph osd tree

# Check PG status
ceph pg stat
```

### 3. Access Ceph Dashboard

The Ceph Dashboard provides a web UI to monitor and manage your cluster.

**Dashboard URL:** `http://<monitor-node-ip>:7000`

**Credentials:**
- **Username:** `admin`
- **Password:** Stored in `/tmp/ceph-dashboard-admin.txt` on the monitor node

To retrieve the password:
```bash
ssh david@<monitor-node> "sudo cat /tmp/ceph-dashboard-admin.txt"
```

Example:
```bash
ssh david@homelab1.martinez-saweczko.es "sudo cat /tmp/ceph-dashboard-admin.txt"
```

The dashboard allows you to:
- Monitor cluster health and status
- View OSD and monitor metrics
- Manage pools and RBD images
- Configure cluster settings
- View performance graphs

### 4. Verify Kubernetes StorageClasses
```bash
# List storage classes
kubectl get storageclasses

# Should output:
# NAME           PROVISIONER        RECLAIMPOLICY
# ceph-rbd       kubernetes.io/rbd  Delete
# ceph-cephfs    cephfs.csi.ceph.io Delete
```

## Using Ceph Storage in MicroK8s

### Create a PVC with RBD
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-storage
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ceph-rbd
  resources:
    requests:
      storage: 5Gi
```

### Deploy a Pod using the PVC
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
spec:
  containers:
  - name: app
    image: busybox
    command: ['sleep', '3600']
    volumeMounts:
    - name: storage
      mountPath: /data
  volumes:
  - name: storage
    persistentVolumeClaim:
      claimName: data-storage
```

### Test the storage
```bash
# Create PVC and pod
kubectl apply -f your-manifest.yaml

# Check PVC status
kubectl get pvc
kubectl describe pvc data-storage

# Check PV (auto-created)
kubectl get pv
kubectl describe pv <pv-name>

# Exec into pod and write data
kubectl exec -it test-pod -- sh
# Inside pod:
echo "test data" > /data/test.txt
exit

# Verify data persists by recreating pod
kubectl delete pod test-pod
kubectl apply -f your-manifest.yaml
kubectl exec -it test-pod -- cat /data/test.txt
```

## Configuration Files Generated

During integration setup, these files are created:

### Kubernetes Secrets
```
ceph-admin-secret (namespace: ceph-storage)
  - Contains Ceph admin key for RBD provisioner
```

### StorageClasses
```
ceph-rbd:
  - RBD provisioner with kubernetes pool
  - Admin credentials from ceph-admin-secret
  - Supports volume expansion
  - Reclaim policy: Delete

ceph-cephfs:
  - CephFS CSI provisioner
  - Supports volume expansion
  - Reclaim policy: Delete
```

## Troubleshooting

### Issue: PVC Pending
```bash
# Check events
kubectl describe pvc <pvc-name>

# Check provisioner logs
kubectl logs -n ceph-storage deployment/csi-rbdplugin-provisioner

# Check Ceph connectivity
kubectl exec -it <pod-name> -- rbd showmapped
```

### Issue: "Permission Denied" for RBD
```bash
# Verify Ceph admin key is correct
kubectl get secret -n ceph-storage ceph-admin-secret -o yaml

# Check Ceph monitors are reachable
kubectl exec -it <pod-name> -- ceph -s

# Verify pool exists
ceph osd lspools
```

### Issue: OSD Down
```bash
# SSH to OSD node
ssh node01

# Check OSD status
ceph osd tree

# Check OSD daemon logs
journalctl -u ceph-osd@* -n 100

# Mark OSD in/out if needed
ceph osd in <osd-id>
ceph osd out <osd-id>
```

### Issue: Monitor Quorum Lost
```bash
# SSH to monitor
ssh node01

# Check monitor status
ceph mon stat

# View monitor dump
ceph mon dump

# Restart monitor if needed
sudo systemctl restart ceph-mon@<hostname>
```

## Performance Tuning

### Ceph Configuration (/etc/ceph/ceph.conf)

Key parameters for homelab:
```ini
# Recovery tuning
osd_recovery_max_active = 3
osd_max_backfills = 1
osd_recovery_sleep = 0.1

# Pool settings
osd_pool_default_size = 3          # Replication factor
osd_pool_default_min_size = 2      # Min for quorum
osd_pool_default_pg_num = 128      # Placement groups
osd_pool_default_pgp_num = 128
```

### RBD Caching
For better performance, enable RBD caching in pod mounts:
```bash
rbd cache = true
rbd cache size = 134217728  # 128MB
rbd cache max dirty = 100663296
rbd cache target dirty = 33554432
```

## Expanding Clusters

### Adding New OSD
1. Add new disk to existing node or new node
2. Re-run the Ceph playbook with updated `ceph_osd_devices`
3. Ceph will auto-rebalance

```bash
# Run with specific OSD setup
ansible-playbook playbooks/ceph.yml \
  -e "ceph_osd_devices=['/dev/sdb','/dev/sdc']" \
  --vault-password-file .vault-pass
```

### Adding New Monitor
1. Add node to `ceph_monitors` group in inventory
2. Re-run Ceph playbook
3. Monitor will auto-join quorum

## Monitoring

### Check cluster health
```bash
ceph health detail
```

### Monitor I/O operations
```bash
ceph osd perf
```

### View pool usage
```bash
ceph df detail
```

### Check pg distribution
```bash
ceph pg dump pgs
```

## Backup & Recovery

### Backup Ceph configuration
```bash
# SSH to first monitor
ssh node01
sudo tar -czf /tmp/ceph-backup-$(date +%Y%m%d).tar.gz /etc/ceph/
```

### Backup RBD images
```bash
# Export RBD image
rbd export kubernetes/image-name /tmp/image-backup.raw
```

## Security Considerations

1. **Network Isolation**: Use `public_network` and `cluster_network` in ceph.conf
2. **Authentication**: All Ceph clients use cephx authentication
3. **Secrets Management**: Use Kubernetes secrets for credentials
4. **RBAC**: Kubernetes RBAC controls who can create PVCs

## Next Steps

1. **Deploy applications** using Ceph storage
2. **Monitor performance** with `ceph -w`
3. **Plan replication** strategy (typically 3 replicas)
4. **Setup backups** for critical data
5. **Tune performance** based on workload

## References

- [Ceph Documentation](https://docs.ceph.com/)
- [Kubernetes Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/)
- [MicroK8s Storage Integration](https://microk8s.io/docs/storage)
