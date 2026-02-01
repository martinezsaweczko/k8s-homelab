# Ceph + Kubernetes Integration Test Guide

This guide walks through testing persistent volume migration across Kubernetes nodes when using Ceph RBD as the storage backend.

## Overview

The test creates a PostgreSQL database with persistent storage, creates test data, then simulates a node failure by shutting down the node. The pod will automatically migrate to another healthy node, and the test verifies that the data persists across the migration.

## Prerequisites

- Kubernetes cluster is running and has at least 2 nodes
- Ceph cluster is configured and accessible
- Ceph CSI RBD driver is installed in your cluster
- `kubectl` is configured and can access your cluster
- PostgreSQL 15 or similar client tools for manual verification

## Test Flow

### Phase 1: Deployment
1. Create `storage-test` namespace
2. Create a 5Gi PersistentVolumeClaim backed by Ceph RBD
3. Deploy PostgreSQL with the PVC mounted
4. Create a test database and table with sample data

### Phase 2: Node Failure Simulation
1. Identify which node the PostgreSQL pod is running on
2. Drain the node (ensure no data loss)
3. Shutdown/poweroff the node
4. Monitor pod migration to another node

### Phase 3: Verification
1. Verify pod started successfully on new node
2. Connect to PostgreSQL and verify test data is present
3. Confirm Ceph volume is attached to new node

## Step-by-Step Instructions

### 1. Deploy Test Application

```bash
./scripts/test-ceph-k8s-migration.sh
```

This script will:
- Create the test namespace and resources
- Deploy PostgreSQL
- Create sample data
- Provide instructions for the next steps

**Expected output:**
```
[Step 1] Deploying test resources...
[Step 2] Creating test database content...
Creating test table and inserting data...
[Step 3] Current pod placement...
Pod running on node: node1
```

### 2. Monitor Pod Status (Terminal 1)

```bash
# Watch pod status and which node it's on
watch -n 1 'kubectl -n storage-test get pod -o wide'

# Or with more details
kubectl -n storage-test get deployment -o wide
```

**Expected output:**
```
NAME                      READY   STATUS    RESTARTS   AGE     IP           NODE      
postgres-xxxxx            1/1     Running   0          5m      10.1.x.x     node1
```

### 3. Get Node Information

```bash
# See all nodes and their status
kubectl get nodes -o wide

# Get detailed info about the node with the pod
kubectl describe node node1
```

### 4. Drain the Node (Terminal 2)

The `drain` command gracefully evicts pods from the node:

```bash
# Drain the node (replace 'node1' with your actual node name)
kubectl drain node1 --ignore-daemonsets --delete-emptydir-data

# Watch the pod migration in Terminal 1
# You should see the pod terminating and restarting on another node
```

### 5. Shutdown the Node

After draining, shutdown the physical node:

**Option A: Using Vagrant (if using Vagrant VMs)**
```bash
cd vagrant/
vagrant halt node1
```

**Option B: Using kubectl (mark as unschedulable)**
```bash
kubectl cordon node1
```

### 6. Verify Data Persistence

Once the pod restarts on the new node, verify the data:

```bash
# Get the new pod name and node
kubectl -n storage-test get pod -o wide

# Connect to the new pod and check the data
kubectl exec -it $(kubectl get pod -n storage-test -l app=postgres -o jsonpath='{.items[0].metadata.name}') -n storage-test -- \
  psql -U testuser -d testdb -c "SELECT * FROM test_data;"
```

**Expected output:**
```
 id |         created_at         |  node_name  |              message              
----+----------------------------+-------------+-----------------------------------
  1 | 2024-01-26 10:30:45.123456 | node1       | Test data created at Fri Jan 26...
(1 row)
```

The data from the original node should still be present!

### 7. Check Ceph Storage

Verify that Ceph properly handled the volume:

```bash
# Access a Ceph monitor node and check RBD status
ssh ceph-monitor-node

# List RBD volumes
sudo rbd ls kubernetes

# Check volume details
sudo rbd du kubernetes

# Check Ceph map info
sudo rbd showmapped
```

## Cleanup

```bash
# Delete the test namespace and all resources
kubectl delete namespace storage-test

# Bring the node back online (if using Vagrant)
cd vagrant/
vagrant up node1

# Or uncordon if using kubectl
kubectl uncordon node1
```

## Expected Results

✅ **Success Indicators:**
- [ ] PostgreSQL pod starts successfully on the first node
- [ ] Test data is created in the database
- [ ] Node drain command completes without errors
- [ ] Pod automatically migrates to a different node
- [ ] Pod reaches "Running" status on the new node
- [ ] PostgreSQL data is intact on the new node
- [ ] Ceph RBD volume is accessible from the new node

❌ **Failure Scenarios:**

**Pod doesn't restart on new node:**
- Check node resources: `kubectl describe nodes`
- Check pod events: `kubectl describe pod <pod-name> -n storage-test`
- Check PVC status: `kubectl get pvc -n storage-test -o wide`

**Data is lost after migration:**
- Check PVC binding: `kubectl get pvc -n storage-test`
- Check RBD mappings: `rbd showmapped`
- Check Ceph cluster health: `ceph status`

**Pod stuck in pending:**
- Check if PVC is bound: `kubectl get pvc -n storage-test`
- Check CSI provisioner logs: `kubectl logs -n ceph-csi-rbd -l app=csi-rbdplugin-provisioner`
- Check node disk space: `df -h` on nodes

## Advanced Testing

### Test Multiple Failovers

1. After pod migrates, uncordon the original node
2. Delete the pod to trigger another migration
3. Repeat to test multiple failover scenarios

### Test with Multiple Replicas

Modify `03-postgres-deployment.yaml` to use multiple replicas (though RBD is RWO, so this requires different approach with statefulsets).

### Performance Testing

Monitor I/O performance during migration:

```bash
# In the running pod, generate some I/O
kubectl exec -it <pod-name> -n storage-test -- \
  dd if=/dev/zero of=/var/lib/postgresql/data/test.img bs=1M count=100

# Monitor network and disk I/O on nodes during failover
```

## Troubleshooting Tips

1. **Check pod events for details:**
   ```bash
   kubectl describe pod <pod-name> -n storage-test
   ```

2. **Check CSI driver logs:**
   ```bash
   kubectl logs -n ceph-csi-rbd -l app=csi-rbdplugin-provisioner --tail=50
   kubectl logs -n ceph-csi-rbd -l app=csi-rbdplugin --tail=50
   ```

3. **Check Ceph status:**
   ```bash
   ssh ceph-monitor-node
   sudo ceph status
   sudo ceph health detail
   ```

4. **Verify StorageClass:**
   ```bash
   kubectl get storageclass ceph-csi-rbd -o yaml
   ```

## References

- [Kubernetes Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [Ceph RBD Documentation](https://docs.ceph.com/en/latest/rbd/index.html)
- [Ceph CSI Documentation](https://docs.ceph.com/en/latest/cephfs/ceph-fuse/)
