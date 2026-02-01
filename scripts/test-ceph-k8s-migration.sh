#!/bin/bash

# Ceph + Kubernetes Integration Test
# This script tests persistent volume migration across nodes

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="storage-test"
DEPLOYMENT="postgres"
KUBECONFIG="${KUBECONFIG:-/var/snap/microk8s/current/credentials/client.config}"
KUBECTL="kubectl --kubeconfig=$KUBECONFIG"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Ceph-K8s Integration Test${NC}"
echo -e "${BLUE}========================================${NC}"

# Step 1: Deploy resources
echo -e "\n${YELLOW}[Step 1] Deploying test resources...${NC}"
$KUBECTL apply -f $(dirname "$0")/test-manifests/00-storageclass.yaml
$KUBECTL apply -f $(dirname "$0")/test-manifests/01-postgres-pvc.yaml
$KUBECTL apply -f $(dirname "$0")/test-manifests/02-postgres-secret.yaml
$KUBECTL apply -f $(dirname "$0")/test-manifests/03-postgres-deployment.yaml

# Wait for deployment to be ready
echo -e "${YELLOW}Waiting for PostgreSQL deployment to be ready...${NC}"
$KUBECTL rollout status deployment/$DEPLOYMENT -n $NAMESPACE --timeout=300s

# Step 2: Create test database and table
echo -e "\n${YELLOW}[Step 2] Creating test database content...${NC}"
POD=$($KUBECTL get pod -n $NAMESPACE -l app=postgres -o jsonpath='{.items[0].metadata.name}')
echo "Pod: $POD"

# Get the secret values
POSTGRES_PASSWORD=$($KUBECTL get secret postgres-secret -n $NAMESPACE -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)
POSTGRES_USER=$($KUBECTL get secret postgres-secret -n $NAMESPACE -o jsonpath='{.data.POSTGRES_USER}' | base64 -d)

# Create a test table with data
echo "Creating test table and inserting data..."
$KUBECTL exec -it $POD -n $NAMESPACE -- psql -U $POSTGRES_USER -d testdb -c "
CREATE TABLE IF NOT EXISTS test_data (
    id SERIAL PRIMARY KEY,
    created_at TIMESTAMP DEFAULT NOW(),
    node_name TEXT,
    message TEXT
);

INSERT INTO test_data (node_name, message)
VALUES (
    '$(hostname)',
    'Test data created at $(date)'
);

SELECT * FROM test_data;
" || echo "Note: Table may already exist"

# Step 3: Get pod and node information
echo -e "\n${YELLOW}[Step 3] Current pod placement...${NC}"
NODE_BEFORE=$($KUBECTL get pod $POD -n $NAMESPACE -o jsonpath='{.spec.nodeName}')
echo -e "${GREEN}Pod running on node: $NODE_BEFORE${NC}"

# Step 4: Get all nodes
echo -e "\n${YELLOW}[Step 4] Available nodes...${NC}"
$KUBECTL get nodes -o wide

# Step 5: Instructions for manual node shutdown
echo -e "\n${YELLOW}[Step 5] Next steps:${NC}"
echo -e "${BLUE}1. Monitor the pod migration:${NC}"
echo "   watch -n 1 'kubectl -n $NAMESPACE get pod -o wide'"
echo ""
echo -e "${BLUE}2. In another terminal, drain and shutdown node $NODE_BEFORE:${NC}"
echo "   kubectl drain $NODE_BEFORE --ignore-daemonsets --delete-emptydir-data"
echo "   # Then poweroff the VM via Vagrant or vagrant halt node1"
echo ""
echo -e "${BLUE}3. Once pod restarts on another node, check data:${NC}"
echo "   kubectl exec -it <pod_name> -n $NAMESPACE -- psql -U $POSTGRES_USER -d testdb -c 'SELECT * FROM test_data;'"
echo ""
echo -e "${GREEN}The original data should be present even after node migration!${NC}"

# Step 6: Display storage information
echo -e "\n${YELLOW}[Step 6] Storage and volume information:${NC}"
echo -e "${BLUE}PersistentVolumeClaim:${NC}"
$KUBECTL get pvc -n $NAMESPACE -o wide

echo -e "\n${BLUE}PersistentVolume:${NC}"
$KUBECTL get pv -o wide

echo -e "\n${BLUE}RBD Block Devices (run on Ceph monitor):${NC}"
echo "   rbd ls kubernetes"
echo "   rbd du kubernetes"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}Test deployment complete!${NC}"
echo -e "${GREEN}========================================${NC}"
