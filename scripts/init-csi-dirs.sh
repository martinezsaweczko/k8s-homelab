#!/bin/bash

# Initialize CSI plugin directories on all nodes
# This ensures the CSI RBD plugin can create staging paths

set -e

KUBECONFIG="${KUBECONFIG:-/var/snap/microk8s/current/credentials/client.config}"
KUBECTL="kubectl --kubeconfig=$KUBECONFIG"

echo "=== Initializing CSI directories on all nodes ==="

# Get all worker nodes
NODES=$($KUBECTL get nodes -o jsonpath='{.items[*].metadata.name}')

for node in $NODES; do
  echo ""
  echo "Setting up CSI directories on $node..."
  
  # Create a temporary pod on the node to initialize directories
  cat <<EOF | $KUBECTL apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: csi-init-$node
  namespace: kube-system
spec:
  nodeSelector:
    kubernetes.io/hostname: $node
  hostPID: true
  hostNetwork: true
  containers:
  - name: init
    image: alpine:latest
    command: ['/bin/sh', '-c']
    args:
    - |
      echo "Creating CSI directories..."
      mkdir -p /host/var/snap/microk8s/common/var/lib/kubelet/plugins/kubernetes.io/csi/rbd.csi.ceph.com
      mkdir -p /host/var/snap/microk8s/common/var/lib/kubelet/plugins/rbd.csi.ceph.com
      chmod -R 755 /host/var/snap/microk8s/common/var/lib/kubelet/plugins
      ls -la /host/var/snap/microk8s/common/var/lib/kubelet/plugins/kubernetes.io/csi/
      echo "Done!"
    volumeMounts:
    - name: host-root
      mountPath: /host
  volumes:
  - name: host-root
    hostPath:
      path: /
  restartPolicy: Never
EOF
  
  # Wait for pod to complete
  sleep 2
  echo "Waiting for initialization pod on $node to complete..."
  $KUBECTL wait --for=condition=Ready pod/csi-init-$node -n kube-system --timeout=30s 2>/dev/null || true
  sleep 2
  
  # Clean up the pod
  $KUBECTL delete pod csi-init-$node -n kube-system 2>/dev/null || true
done

echo ""
echo "✓ CSI directories initialized on all nodes"
