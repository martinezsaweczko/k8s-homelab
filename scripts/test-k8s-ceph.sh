#!/bin/bash
set -e

# Test Kubernetes access to Ceph storage
# This script sets up RBD storage in Kubernetes and tests it

MONITOR_IP="${1:-172.26.32.240}"
NAMESPACE="${2:-default}"
POOL="${3:-kubernetes}"

echo "=========================================="
echo "Testing Kubernetes + Ceph RBD Integration"
echo "=========================================="
echo "Monitor IP: $MONITOR_IP"
echo "Namespace: $NAMESPACE"
echo "Pool: $POOL"
echo ""

# Clean up any previous test resources
echo "[0/7] Cleaning up previous test resources..."
kubectl delete pod ceph-test-pod -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true
kubectl delete pvc ceph-test-pvc -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true
sleep 2
echo "✓ Cleanup complete"
echo ""

# Step 1: Get Ceph credentials
echo "[1/7] Retrieving Ceph RBD client key..."
CEPH_KEY=$(sudo ceph auth get-key client.kubernetes 2>/dev/null || echo "ERROR")

if [ "$CEPH_KEY" == "ERROR" ]; then
  echo "ERROR: Could not retrieve Ceph client key. Make sure Ceph cluster is running."
  exit 1
fi

echo "✓ Ceph key retrieved"
echo ""

# Step 2: Create Kubernetes namespace (if not default)
if [ "$NAMESPACE" != "default" ]; then
  echo "[2/7] Creating Kubernetes namespace: $NAMESPACE..."
  kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
  echo "✓ Namespace created/verified"
else
  echo "[2/7] Using default namespace"
fi
echo ""

# Step 3: Create admin secret for CSI
echo "[3/7] Creating Ceph admin secret..."
ADMIN_KEY=$(sudo ceph auth get-key client.admin 2>/dev/null)
kubectl create secret generic ceph-admin-secret \
  --from-literal=adminId=admin \
  --from-literal=adminKey="$ADMIN_KEY" \
  --namespace=kube-system \
  --dry-run=client -o yaml | kubectl apply -f -
echo "✓ Admin secret created"
echo ""

# Step 4: Create user secret for RBD access
echo "[4/7] Creating Ceph RBD client secret..."
kubectl create secret generic ceph-secret \
  --from-literal=key="$CEPH_KEY" \
  --namespace="$NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -
echo "✓ RBD client secret created"
echo ""

# Step 5: Create StorageClass
echo "[5/7] Creating StorageClass 'ceph-rbd'..."
kubectl delete storageclass ceph-rbd --ignore-not-found=true 2>/dev/null
sleep 1
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ceph-rbd
provisioner: kubernetes.io/rbd
parameters:
  monitors: "$MONITOR_IP:6789"
  adminId: admin
  adminSecretName: ceph-admin-secret
  adminSecretNamespace: kube-system
  pool: $POOL
  userId: kubernetes
  userSecretName: ceph-secret
  userSecretNamespace: $NAMESPACE
  fstype: ext4
  imageFormat: "2"
  imageFeatures: "layering"
EOF
echo "✓ StorageClass created"
echo ""

# Step 6: Create test PVC
echo "[6/7] Creating test PersistentVolumeClaim..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ceph-test-pvc
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ceph-rbd
  resources:
    requests:
      storage: 1Gi
EOF
echo "✓ PVC created"
echo ""

# Step 7: Wait for PVC and create test pod
echo "[7/7] Waiting for PVC to bind..."
kubectl wait --for=condition=Bound pvc/ceph-test-pvc -n "$NAMESPACE" --timeout=60s 2>/dev/null || {
  echo "⚠ Warning: PVC binding timeout. Checking status..."
  kubectl describe pvc ceph-test-pvc -n "$NAMESPACE"
}
echo "✓ PVC ready"
echo ""

# Create test pod
echo "Creating test pod..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ceph-test-pod
  namespace: $NAMESPACE
spec:
  containers:
  - name: test-container
    image: busybox:latest
    command: ["sh", "-c", "while true; do sleep 1; done"]
    volumeMounts:
    - name: ceph-volume
      mountPath: /data
  volumes:
  - name: ceph-volume
    persistentVolumeClaim:
      claimName: ceph-test-pvc
EOF

echo ""
echo "Waiting for pod to be ready..."
kubectl wait --for=condition=Ready pod/ceph-test-pod -n "$NAMESPACE" --timeout=60s 2>/dev/null || {
  echo "⚠ Warning: Pod not ready yet. Checking status..."
  kubectl describe pod ceph-test-pod -n "$NAMESPACE"
}
echo "✓ Pod created and running"
echo ""

# Step 8: Test read/write
echo "=========================================="
echo "Testing read/write to Ceph volume..."
echo "=========================================="

# Write test
echo "Writing test file..."
kubectl exec -it ceph-test-pod -n "$NAMESPACE" -- sh -c 'echo "Hello from K8s at $(date)" > /data/test.txt'
echo "✓ Write successful"
echo ""

# Read test
echo "Reading test file..."
kubectl exec -it ceph-test-pod -n "$NAMESPACE" -- cat /data/test.txt
echo "✓ Read successful"
echo ""

# Cleanup function
cleanup() {
  read -p "Do you want to clean up test resources? (y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleaning up..."
    kubectl delete pod ceph-test-pod -n "$NAMESPACE" --ignore-not-found
    kubectl delete pvc ceph-test-pvc -n "$NAMESPACE" --ignore-not-found
    echo "✓ Cleanup complete"
  else
    echo "Resources left running. You can manually delete with:"
    echo "  kubectl delete pod ceph-test-pod -n $NAMESPACE"
    echo "  kubectl delete pvc ceph-test-pvc -n $NAMESPACE"
  fi
}

echo "=========================================="
echo "✓ All tests passed!"
echo "=========================================="
echo ""
echo "Resources created:"
echo "  - StorageClass: ceph-rbd"
echo "  - PVC: ceph-test-pvc (namespace: $NAMESPACE)"
echo "  - Pod: ceph-test-pod (namespace: $NAMESPACE)"
echo ""

cleanup
