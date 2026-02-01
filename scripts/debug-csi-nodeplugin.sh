#!/bin/bash

# Debug and fix CSI RBD nodeplugin staging path issue

KUBECONFIG="${KUBECONFIG:-/var/snap/microk8s/current/credentials/client.config}"
KUBECTL="kubectl --kubeconfig=$KUBECONFIG"

echo "=== Checking CSI nodeplugin configuration ==="

# Get nodeplugin pod details
echo ""
echo "Nodeplugin pods:"
$KUBECTL get pods -n ceph-csi-rbd -o wide | grep nodeplugin

echo ""
echo "=== Checking nodeplugin container volume mounts ==="
POD=$($KUBECTL get pod -n ceph-csi-rbd -l app.kubernetes.io/name=ceph-csi-rbd,app.kubernetes.io/component=nodeplugin -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || $KUBECTL get pod -n ceph-csi-rbd -l app=ceph-csi-rbd-nodeplugin -o jsonpath='{.items[0].metadata.name}')

if [ -z "$POD" ]; then
  echo "Could not find nodeplugin pod"
  exit 1
fi

echo "Using pod: $POD"

echo ""
echo "=== Volume mounts ==="
$KUBECTL get pod $POD -n ceph-csi-rbd -o jsonpath='{.spec.containers[0].volumeMounts}' | jq .

echo ""
echo "=== Pod volumes ==="
$KUBECTL get pod $POD -n ceph-csi-rbd -o jsonpath='{.spec.volumes}' | jq .

echo ""
echo "=== Checking if kubelet plugin directory exists ==="
$KUBECTL exec $POD -n ceph-csi-rbd -c csi-rbdplugin -- ls -la /var/lib/kubelet/plugins/kubernetes.io/csi/ 2>/dev/null || echo "Directory not found in container"

echo ""
echo "=== Pod hostPath mounts (if any) ==="
$KUBECTL get pod $POD -n ceph-csi-rbd -o yaml | grep -A 20 "volumes:"
