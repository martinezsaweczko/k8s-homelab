#!/bin/bash

# Cleanup script for Ceph-K8s integration test

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

NAMESPACE="storage-test"
KUBECONFIG="${KUBECONFIG:-/var/snap/microk8s/current/credentials/client.config}"
KUBECTL="kubectl --kubeconfig=$KUBECONFIG"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Ceph-K8s Integration Test - Cleanup${NC}"
echo -e "${BLUE}========================================${NC}"

echo -e "${YELLOW}Deleting storage-test namespace...${NC}"
$KUBECTL delete namespace $NAMESPACE --ignore-not-found=true

echo -e "${YELLOW}Waiting for namespace deletion...${NC}"
for i in {1..30}; do
  if ! $KUBECTL get namespace $NAMESPACE &>/dev/null; then
    echo -e "${GREEN}Namespace deleted successfully${NC}"
    break
  fi
  echo -n "."
  sleep 2
done

echo -e "\n${YELLOW}Checking for remaining resources...${NC}"
$KUBECTL get pvc --all-namespaces | grep -i ceph || echo "No Ceph PVCs found"
$KUBECTL get pv | grep -i ceph || echo "No Ceph PVs found"

echo -e "\n${YELLOW}If using Vagrant, bringing nodes back online...${NC}"
if [ -d "vagrant" ]; then
  echo -e "${BLUE}To restore nodes, run:${NC}"
  echo "  cd vagrant && vagrant up"
  echo "  kubectl uncordon node1 node2 node3"
fi

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup complete!${NC}"
echo -e "${GREEN}========================================${NC}"
