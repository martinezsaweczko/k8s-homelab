#!/bin/bash

# Fix CSI RBD nodeplugin staging path issue by patching the daemonset

KUBECONFIG="${KUBECONFIG:-/var/snap/microk8s/current/credentials/client.config}"
KUBECTL="kubectl --kubeconfig=$KUBECONFIG"

echo "=== Patching CSI nodeplugin daemonset ==="

# Check if the daemonset exists
if ! $KUBECTL get ds ceph-csi-rbd-nodeplugin -n ceph-csi-rbd &>/dev/null; then
  echo "Error: Could not find ceph-csi-rbd-nodeplugin daemonset"
  exit 1
fi

echo "Found ceph-csi-rbd-nodeplugin daemonset"

# Patch the daemonset to add proper volume mounts for MicroK8s
echo "Patching daemonset with proper volume mounts..."

$KUBECTL patch ds ceph-csi-rbd-nodeplugin -n ceph-csi-rbd --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/volumes/-",
    "value": {
      "name": "plugin-dir",
      "hostPath": {
        "path": "/var/snap/microk8s/common/var/lib/kubelet/plugins_registry",
        "type": "DirectoryOrCreate"
      }
    }
  },
  {
    "op": "add",
    "path": "/spec/template/spec/volumes/-",
    "value": {
      "name": "mountpoint-dir",
      "hostPath": {
        "path": "/var/snap/microk8s/common/var/lib/kubelet/plugins",
        "type": "DirectoryOrCreate"
      }
    }
  },
  {
    "op": "add",
    "path": "/spec/template/spec/volumes/-",
    "value": {
      "name": "csi-plugins-dir",
      "hostPath": {
        "path": "/var/snap/microk8s/common/var/lib/kubelet/plugins/kubernetes.io/csi",
        "type": "DirectoryOrCreate"
      }
    }
  }
]'

if [ $? -eq 0 ]; then
  echo "✓ Volumes patched successfully"
else
  echo "! Volumes patch may have already been applied or failed"
fi

# Now patch the container volumeMounts
echo ""
echo "Patching container volumeMounts..."

$KUBECTL patch ds ceph-csi-rbd-nodeplugin -n ceph-csi-rbd --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/volumeMounts/-",
    "value": {
      "name": "plugin-dir",
      "mountPath": "/var/lib/kubelet/plugins_registry"
    }
  },
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/volumeMounts/-",
    "value": {
      "name": "mountpoint-dir",
      "mountPath": "/var/lib/kubelet/plugins"
    }
  },
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/volumeMounts/-",
    "value": {
      "name": "csi-plugins-dir",
      "mountPath": "/var/lib/kubelet/plugins/kubernetes.io/csi"
    }
  }
]'

if [ $? -eq 0 ]; then
  echo "✓ VolumeMounts patched successfully"
  echo ""
  echo "Waiting for nodeplugin pods to restart..."
  $KUBECTL rollout restart ds ceph-csi-rbd-nodeplugin -n ceph-csi-rbd
  echo ""
  echo "Waiting for rollout to complete..."
  $KUBECTL rollout status ds ceph-csi-rbd-nodeplugin -n ceph-csi-rbd --timeout=60s
  echo ""
  echo "✓ CSI nodeplugin patched and restarted"
else
  echo "! VolumeMounts patch may have already been applied or failed"
fi
