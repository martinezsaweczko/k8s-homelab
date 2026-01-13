#!/bin/bash
set -e

# Test Kubernetes access to Ceph storage using CSI RBD driver
# This script installs Ceph CSI RBD driver and tests K8s + Ceph integration

MONITOR_IP="${1:-172.26.32.240}"
NAMESPACE="${2:-default}"
POOL="${3:-kubernetes}"
CSI_VERSION="${4:-v3.9.0}"

echo "=========================================="
echo "Testing K8s + Ceph RBD CSI Integration"
echo "=========================================="
echo "Monitor IP: $MONITOR_IP"
echo "Namespace: $NAMESPACE"
echo "Pool: $POOL"
echo "CSI Version: $CSI_VERSION"
echo ""

# Step 1: Check if CSI RBD is already installed
echo "[1/6] Checking for Ceph CSI RBD driver..."

# Check if helm is installed
if ! command -v helm &> /dev/null; then
  echo "ERROR: helm is not installed. Please install helm first:"
  echo "  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
  exit 1
fi

# Check if kubectl is accessible
if ! kubectl cluster-info &>/dev/null; then
  echo "ERROR: Cannot connect to Kubernetes cluster"
  echo "Please ensure kubeconfig is properly configured:"
  echo "  export KUBECONFIG=~/.kube/config"
  echo "Or run: kubectl config view"
  exit 1
fi

# Ensure helm uses the same kubeconfig as kubectl
if [ -z "$KUBECONFIG" ]; then
  # Try common kubeconfig locations in order of preference
  if [ -f /home/david/.kube/config ]; then
    export KUBECONFIG=/home/david/.kube/config
  elif [ -f ~/.kube/config ]; then
    export KUBECONFIG=~/.kube/config
  elif [ -f /root/.kube/config ]; then
    export KUBECONFIG=/root/.kube/config
  elif [ -f /etc/kubernetes/admin.conf ]; then
    export KUBECONFIG=/etc/kubernetes/admin.conf
  fi
fi

# Verify KUBECONFIG is set and valid
if [ -z "$KUBECONFIG" ] || [ ! -f "$KUBECONFIG" ]; then
  echo "ERROR: KUBECONFIG not found at $KUBECONFIG"
  echo "Please set KUBECONFIG environment variable to a valid kubeconfig file"
  exit 1
fi

echo "Using KUBECONFIG: $KUBECONFIG"
echo ""

if kubectl get storageclass ceph-csi-rbd &>/dev/null; then
  echo "✓ CSI RBD already installed"
else
  echo "⚠ CSI RBD not found, installing..."

  # Create ceph-csi namespace
  kubectl create namespace ceph-csi-rbd --dry-run=client -o yaml | kubectl apply -f -

  # Add Helm repo and install CSI RBD
  helm repo add ceph-csi https://ceph.github.io/csi-charts 2>/dev/null || true
  helm repo update

  # Install CSI RBD driver with proper timeout
  echo "Installing Ceph CSI RBD driver (this may take a minute)..."
  helm install ceph-csi-rbd ceph-csi/ceph-csi-rbd \
    --namespace ceph-csi-rbd \
    --set cephClusterSecretName=ceph-secret \
    --set cephClusterSecretNamespace=ceph-csi-rbd \
    --wait --timeout 5m || {
    echo "⚠ Helm install timed out or failed, continuing anyway..."
  }

  echo "✓ CSI RBD installation attempted"
fi
echo ""

# Step 2: Get Ceph credentials
echo "[2/6] Retrieving Ceph RBD client key..."
CEPH_KEY=$(sudo ceph auth get-key client.kubernetes 2>/dev/null || echo "ERROR")

if [ "$CEPH_KEY" == "ERROR" ]; then
  echo "ERROR: Could not retrieve Ceph client key. Make sure Ceph cluster is running."
  exit 1
fi

echo "✓ Ceph key retrieved"
echo ""

# Step 3: Create namespace (if not default)
if [ "$NAMESPACE" != "default" ]; then
  echo "[3/6] Creating Kubernetes namespace: $NAMESPACE..."
  kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
  echo "✓ Namespace created/verified"
else
  echo "[3/6] Using default namespace"
fi
echo ""

# Step 4: Create Ceph credentials secret with monitor configuration
echo "[4/6] Creating Ceph credentials secret..."
CEPH_MON_NAME=$(sudo ceph config get mon name 2>/dev/null | head -1 | awk '{print $NF}')
CEPH_CLUSTER_ID=$(sudo ceph fsid 2>/dev/null)

# Get monitor addresses
CEPH_MONITORS=$(sudo ceph mon dump | grep "^[0-9]" | awk '{print $3}' | tr '\n' ',' | sed 's/,$//')

# Create ceph.conf content
CEPH_CONF="[global]
fsid = $CEPH_CLUSTER_ID
mon_host = $CEPH_MONITORS
"

# Create secret in ceph-csi-rbd namespace (required for provisioner)
kubectl create secret generic ceph-secret \
  --from-literal=userID=kubernetes \
  --from-literal=userKey="$CEPH_KEY" \
  --from-literal=ceph.conf="$CEPH_CONF" \
  --namespace=ceph-csi-rbd \
  --dry-run=client -o yaml | kubectl apply -f -

# Also create in target namespace
kubectl create secret generic ceph-secret \
  --from-literal=userID=kubernetes \
  --from-literal=userKey="$CEPH_KEY" \
  --from-literal=ceph.conf="$CEPH_CONF" \
  --namespace="$NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✓ Secret created in ceph-csi-rbd and $NAMESPACE namespaces"
echo "  Monitors: $CEPH_MONITORS"
echo ""

# Step 5: Create StorageClass
echo "[5/6] Creating StorageClass 'ceph-csi-rbd'..."
kubectl delete storageclass ceph-csi-rbd --ignore-not-found=true 2>/dev/null || true
sleep 1

cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ceph-csi-rbd
provisioner: rbd.csi.ceph.com
parameters:
  clusterID: $CEPH_CLUSTER_ID
  pool: $POOL
  imageFeatures: layering
  csi.storage.k8s.io/provisioner-secret-name: ceph-secret
  csi.storage.k8s.io/provisioner-secret-namespace: ceph-csi-rbd
  csi.storage.k8s.io/controller-expand-secret-name: ceph-secret
  csi.storage.k8s.io/controller-expand-secret-namespace: ceph-csi-rbd
  csi.storage.k8s.io/node-stage-secret-name: ceph-secret
  csi.storage.k8s.io/node-stage-secret-namespace: $NAMESPACE
reclaimPolicy: Delete
allowVolumeExpansion: true
EOF

echo "✓ StorageClass created"
echo ""

# Step 6: Clean up old test resources
echo "[6/6] Cleaning up previous test resources..."
kubectl delete pod ceph-test-pod -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true
kubectl delete pvc ceph-test-pvc -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true
sleep 2
echo "✓ Cleanup complete"
echo ""

# Create test PVC
echo "Creating test PersistentVolumeClaim..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ceph-test-pvc
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ceph-csi-rbd
  resources:
    requests:
      storage: 1Gi
EOF

echo ""
echo "Waiting for PVC to bind..."
kubectl wait --for=condition=Bound pvc/ceph-test-pvc -n "$NAMESPACE" --timeout=60s 2>/dev/null || {
  echo "⚠ Warning: PVC binding timeout. Checking status..."
  kubectl describe pvc ceph-test-pvc -n "$NAMESPACE"
  exit 1
}
echo "✓ PVC bound successfully"
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
kubectl wait --for=condition=Ready pod/ceph-test-pod -n "$NAMESPACE" --timeout=120s 2>/dev/null || {
  echo "⚠ Warning: Pod not ready yet. Checking status..."
  kubectl describe pod ceph-test-pod -n "$NAMESPACE"
  echo ""
  echo "Checking CSI driver pods..."
  kubectl get pods -n ceph-csi-rbd
  exit 1
}
echo "✓ Pod created and running"
echo ""

# Test read/write
echo "=========================================="
echo "Testing read/write to Ceph volume..."
echo "=========================================="

# Write test
echo "Writing test file..."
kubectl exec ceph-test-pod -n "$NAMESPACE" -- sh -c 'echo "Hello from K8s at $(date)" > /data/test.txt'
echo "✓ Write successful"
echo ""

# Read test
echo "Reading test file..."
kubectl exec ceph-test-pod -n "$NAMESPACE" -- cat /data/test.txt
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
echo "  - StorageClass: ceph-csi-rbd"
echo "  - PVC: ceph-test-pvc (namespace: $NAMESPACE)"
echo "  - Pod: ceph-test-pod (namespace: $NAMESPACE)"
echo ""

cleanup
