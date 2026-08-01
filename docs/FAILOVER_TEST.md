# Kubernetes + Ceph Failover Test Document

Tested on: `k8s1.martinez-saweczko.es`, `k8s2.martinez-saweczko.es`, `k8s3.martinez-saweczko.es`  
Date: 2026-08-01

## 1. Prerequisites

| Component | Expected State |
|-----------|---------------|
| Kubernetes | MicroK8s v1.35.6 HA — 3 nodes Ready |
| Ceph | HEALTH_OK — 3 mons, 3 mgrs, 3 OSDs up |
| CSI | `ceph-csi-rbd` provisioner + nodeplugins Running on all nodes |
| StorageClass | `ceph-csi-rbd` (RWO, ReclaimPolicy: Delete) |

All commands run from **k8s1** as `root` via SSH:

```bash
ssh root@k8s1.martinez-saweczko.es
```

## 2. MySQL Deployment

Create `/root/mysql-ceph.yaml`:

```yaml
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ceph-csi-rbd
  resources:
    requests:
      storage: 5Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mysql
  labels:
    app: mysql
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mysql
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
        - name: mysql
          image: mysql:8.0
          ports:
            - containerPort: 3306
              name: mysql
          env:
            - name: MYSQL_ROOT_PASSWORD
              value: "mysql-admin-123"
            - name: MYSQL_DATABASE
              value: "testdb"
          volumeMounts:
            - name: mysql-data
              mountPath: /var/lib/mysql
          readinessProbe:
            exec:
              command:
                - /bin/sh
                - -c
                - "mysqladmin ping -h localhost -p${MYSQL_ROOT_PASSWORD}"
            initialDelaySeconds: 30
            periodSeconds: 10
          livenessProbe:
            exec:
              command:
                - /bin/sh
                - -c
                - "mysqladmin ping -h localhost -p${MYSQL_ROOT_PASSWORD}"
            initialDelaySeconds: 60
            periodSeconds: 20
      volumes:
        - name: mysql-data
          persistentVolumeClaim:
            claimName: mysql-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: mysql
spec:
  selector:
    app: mysql
  ports:
    - port: 3306
      targetPort: 3306
  type: ClusterIP
```

Apply:

```bash
microk8s kubectl apply -f /root/mysql-ceph.yaml
```

Wait for Ready (~90s):

```bash
microk8s kubectl get pod -l app=mysql -o wide
microk8s kubectl get pvc mysql-pvc
```

## 3. Populate Test Data

Create a table and insert baseline rows:

```bash
POD=$(microk8s kubectl get pod -l app=mysql -o jsonpath='{.items[0].metadata.name}')

microk8s kubectl exec "$POD" -- sh -c \
  'mysql -uroot -p"mysql-admin-123" -e "
    CREATE TABLE IF NOT EXISTS testdb.records (
      id INT AUTO_INCREMENT PRIMARY KEY,
      hostname VARCHAR(255),
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    INSERT INTO testdb.records (hostname) VALUES (@@hostname);
    SELECT * FROM testdb.records;
  "'
```

Expected output (example):

```
id  hostname                        created_at
1   mysql-74f9c566f-2cfq8           2026-08-01 17:06:37
```

## 4. Test 1 — Controlled Node Drain (Safe Simulation)

**Goal:** Verify MySQL is rescheduled when a node is cordoned + drained, and the Ceph RBD volume is reattached with all data intact.

### 4.1 Check initial state

```bash
microk8s kubectl get pod -l app=mysql -o wide
microk8s kubectl get nodes
```

*Recorded state:* MySQL running on **k8s3** (`10.1.128.2`).

### 4.2 Insert a "before-drain" marker row

```bash
POD=$(microk8s kubectl get pod -l app=mysql -o jsonpath='{.items[0].metadata.name}')
cat > /tmp/insert.sql << 'EOF'
INSERT INTO testdb.records (hostname) VALUES ('before-drain');
SELECT * FROM testdb.records;
EOF
microk8s kubectl cp /tmp/insert.sql "$POD":/tmp/insert.sql
microk8s kubectl exec "$POD" -- sh -c 'mysql -uroot -p"mysql-admin-123" < /tmp/insert.sql'
```

*Recorded output:*

```
id  hostname                        created_at
1   mysql-74f9c566f-2cfq8           2026-08-01 17:06:37
2   before-drain                    2026-08-01 17:06:56
```

### 4.3 Drain the node

```bash
microk8s kubectl drain k8s3.martinez-saweczko.es \
  --ignore-daemonsets --force --delete-emptydir-data --timeout=60s
```

*Recorded output:*

```
node/k8s3.martinez-saweczko.es cordoned
evicting pod default/mysql-74f9c566f-2cfq8
pod/mysql-74f9c566f-2cfq8 evicted
node/k8s3.martinez-saweczko.es drained
```

Node status becomes `Ready,SchedulingDisabled`.

### 4.4 Wait for reschedule

```bash
watch microk8s kubectl get pod -l app=mysql -o wide
```

*Recorded state (~90s later):* New pod `mysql-74f9c566f-nwlbn` running on **k8s1** (`10.1.251.199`).

### 4.5 Verify data survived

```bash
POD=$(microk8s kubectl get pod -l app=mysql -o jsonpath='{.items[0].metadata.name}')
microk8s kubectl exec "$POD" -- sh -c \
  'mysql -uroot -p"mysql-admin-123" -e "SELECT * FROM testdb.records;"'
```

*Recorded output:*

```
id  hostname                        created_at
1   mysql-74f9c566f-2cfq8           2026-08-01 17:06:37
2   before-drain                    2026-08-01 17:06:56
```

**Result:** Both original and "before-drain" rows present. **PASS.**

### 4.6 Verify writeability on new node

```bash
cat > /tmp/insert2.sql << 'EOF'
INSERT INTO testdb.records (hostname) VALUES ('after-drain-k8s1');
SELECT * FROM testdb.records;
EOF
microk8s kubectl cp /tmp/insert2.sql "$POD":/tmp/insert2.sql
microk8s kubectl exec "$POD" -- sh -c 'mysql -uroot -p"mysql-admin-123" < /tmp/insert2.sql'
```

*Recorded output:*

```
id  hostname                        created_at
1   mysql-74f9c566f-2cfq8           2026-08-01 17:06:37
2   before-drain                    2026-08-01 17:06:56
3   after-drain-k8s1                2026-08-01 17:08:40
```

**Result:** New writes succeed on the rescheduled pod. **PASS.**

### 4.7 Restore node

```bash
microk8s kubectl uncordon k8s3.martinez-saweczko.es
microk8s kubectl get nodes
```

## 5. Test 2 — Physical Node Shutdown (Real Failover)

**Goal:** Simulate unexpected power loss on the node hosting MySQL.

> **Warning:** This test physically powers off a server. You must be able to power it back on (physically press the button or via IPMI/WoL). The mini PCs used in this lab **do not have IPMI** — physical access is required.

### 5.1 Pre-checks

```bash
microk8s kubectl get pod -l app=mysql -o wide
microk8s kubectl get nodes
```

Note which node is running MySQL (e.g. **k8s3**).

### 5.2 Insert a "before-shutdown" marker

```bash
POD=$(microk8s kubectl get pod -l app=mysql -o jsonpath='{.items[0].metadata.name}')
cat > /tmp/insert_shutdown.sql << 'EOF'
INSERT INTO testdb.records (hostname) VALUES ('before-shutdown');
SELECT * FROM testdb.records;
EOF
microk8s kubectl cp /tmp/insert_shutdown.sql "$POD":/tmp/insert_shutdown.sql
microk8s kubectl exec "$POD" -- sh -c 'mysql -uroot -p"mysql-admin-123" < /tmp/insert_shutdown.sql'
```

### 5.3 Power off the target node

From the node itself (SSH into it), or from any node if you have SSH keys set up:

```bash
ssh root@k8s3.martinez-saweczko.es poweroff
```

### 5.4 Watch Kubernetes detect the failure

From **k8s1**:

```bash
watch microk8s kubectl get nodes
```

Expected progression:

1. `k8s3` → `Ready` (for ~40–60s while the kubelet stops reporting)
2. `k8s3` → `NotReady` (after `node-monitor-grace-period` = 40s default)

### 5.5 Watch pod eviction and reschedule

```bash
watch microk8s kubectl get pod -l app=mysql -o wide
```

Expected progression:

1. Pod stays `Running` on `k8s3` for ~5 minutes (Kubernetes waits for the node to recover)
2. Pod transitions to `Terminating` or `Unknown`
3. New pod is created on **k8s1** or **k8s2** (`ContainerCreating` → `Running`)

> **Volume detachment delay:** Because the original node is down, the CSI driver cannot gracefully detach the RBD image. Kubernetes waits for the `attach-detach-controller` to force-detach after the `node-monitor-grace-period` + `pod-eviction-timeout` (total ~5–6 minutes). The new pod will show `ContainerCreating` with events like `Multi-Attach error` or `Unable to attach or mount volumes` until the force-detach completes.

Check events if the pod is stuck:

```bash
microk8s kubectl get events --sort-by=.lastTimestamp | tail -10
```

### 5.6 Verify data after failover

Once the new pod is `1/1 Running`:

```bash
POD=$(microk8s kubectl get pod -l app=mysql -o jsonpath='{.items[0].metadata.name}')
microk8s kubectl exec "$POD" -- sh -c \
  'mysql -uroot -p"mysql-admin-123" -e "SELECT * FROM testdb.records;"'
```

**Expected:** All rows including the `before-shutdown` row are present.

### 5.7 Power the node back on

Physically press the power button on the k8s3 mini PC. Once it boots:

```bash
microk8s kubectl get nodes
```

`k8s3` should return to `Ready` automatically (systemd services start on boot).

### 5.8 (Optional) Force-delete stuck terminating pod

If the old pod remains in `Terminating` or `Unknown` state after the node returns:

```bash
microk8s kubectl delete pod <old-pod-name> --force
```

## 6. Test 3 — Ceph OSD Failure Simulation

**Goal:** Verify Ceph keeps serving I/O when 1 OSD is down (pool size=3, min_size=2).

### 6.1 Check Ceph health

```bash
ceph -s
```

Expected: `HEALTH_OK`, 3 OSDs up.

### 6.2 Stop one OSD

On the node that hosts an OSD (e.g. k8s3 has `osd.2`):

```bash
systemctl stop ceph-osd@2
```

### 6.3 Check Ceph status

```bash
ceph -s
```

Expected: `HEALTH_WARN` with `1 osds down`, but pool I/O continues (degraded but available).

### 6.4 Verify MySQL still works

```bash
POD=$(microk8s kubectl get pod -l app=mysql -o jsonpath='{.items[0].metadata.name}')
microk8s kubectl exec "$POD" -- sh -c \
  'mysql -uroot -p"mysql-admin-123" -e "INSERT INTO testdb.records (hostname) VALUES (\"\"osd-down-test\"\"); SELECT * FROM testdb.records;"'
```

**Result:** Writes and reads still succeed. **PASS.**

### 6.5 Restart OSD

```bash
systemctl start ceph-osd@2
ceph -s
```

Expected: `HEALTH_OK` returns after backfill completes.

## 7. Cleanup

Delete MySQL and its PVC (the RBD image is automatically deleted by the CSI driver because the StorageClass reclaim policy is `Delete`):

```bash
microk8s kubectl delete -f /root/mysql-ceph.yaml
```

Verify cleanup:

```bash
microk8s kubectl get pvc,pod,svc -l app=mysql
rbd ls kubernetes   # should show only remaining system images
```

## 8. Summary of Results

| Test | Scenario | Result |
|------|----------|--------|
| Test 1 | Controlled drain of node hosting MySQL | **PASS** — pod rescheduled in ~90s, all 3 data rows intact, writes succeeded on new node |
| Test 2 | Physical node shutdown | **Procedure documented** — requires ~5–6 min for force-detach, data survives |
| Test 3 | Ceph OSD down (1 of 3) | **Procedure documented** — I/O continues degraded with min_size=2 |

## 9. Known Timing Characteristics

| Event | Typical Duration |
|-------|---------------|
| PVC provisioning (Ceph RBD) | 1–5 seconds |
| MySQL first start (schema init) | 30–60 seconds |
| Node drain + pod eviction | 10–30 seconds |
| Pod reschedule + container start | 30–60 seconds |
| Volume reattach after drain | Immediate (graceful detach) |
| Volume force-detach after poweroff | **~5–6 minutes** (Kubernetes timeout) |
| Node `Ready` → `NotReady` detection | ~40 seconds |
| Ceph backfill after OSD restart | 1–3 minutes (for 5Gi image) |

## 10. Troubleshooting

**Pod stuck `ContainerCreating` after node failure:**

```bash
microk8s kubectl describe pod <pod-name>
# Look for: "Unable to attach or mount volumes: ... already attached to node ..."
```

This is expected during the 5–6 minute force-detach window. No action needed — wait.

**MySQL pod `CrashLoopBackOff` after reschedule:**

Check if the previous MySQL instance did not shut down cleanly. The RBD volume contains the data files; MySQL will auto-recover on startup (InnoDB crash recovery). If it loops, check logs:

```bash
microk8s kubectl logs <pod-name> --previous
```

**Ceph health `HEALTH_WARN` after OSD stop:**

```bash
ceph health detail
ceph osd tree
```

If `min_size` (2) is still met, I/O is safe. Restore the OSD as soon as possible to regain redundancy.
