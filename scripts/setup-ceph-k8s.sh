#!/bin/bash
# Quick start guide for Ceph + MicroK8s integration

set -e

echo "=== Ceph + MicroK8s Homelab Setup ==="
echo

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check prerequisites
echo "Checking prerequisites..."
if ! command -v ansible &> /dev/null; then
    echo -e "${RED}Ansible is not installed${NC}"
    exit 1
fi

if ! command -v ssh &> /dev/null; then
    echo -e "${RED}SSH is not installed${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Prerequisites met${NC}"
echo

# Check inventory
echo "Checking inventory..."
if [ ! -f "inventories/hosts.yml" ]; then
    echo -e "${YELLOW}⚠ inventories/hosts.yml not found${NC}"
    echo "Creating from example..."
    cp inventories/hosts.example.yml inventories/hosts.yml
    echo -e "${YELLOW}⚠ Please edit inventories/hosts.yml with your hosts${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Inventory found${NC}"
echo

# Step 1: Apply common configuration
echo "Step 1: Applying OS configuration..."
ansible-playbook playbooks/site.yml \
  --tags "common" \
  --vault-password-file .vault-pass \
  -i inventories/hosts.yml

echo -e "${GREEN}✓ OS configuration applied${NC}"
echo

# Step 2: Install Kubernetes
echo "Step 2: Installing MicroK8s..."
ansible-playbook playbooks/kubernetes.yml \
  --vault-password-file .vault-pass \
  -i inventories/hosts.yml

echo -e "${GREEN}✓ MicroK8s installed${NC}"
echo

# Step 3: Install Ceph
echo "Step 3: Installing Ceph..."
ansible-playbook playbooks/ceph.yml \
  --vault-password-file .vault-pass \
  -i inventories/hosts.yml

echo -e "${GREEN}✓ Ceph installed and integrated${NC}"
echo

# Verification
echo "=== Verification ==="
echo

# Check K8s
echo "Kubernetes cluster status:"
microk8s kubectl get nodes
echo

echo "Storage classes:"
microk8s kubectl get storageclasses
echo

echo "Ceph cluster status:"
ceph -s
echo

echo -e "${GREEN}✓ Setup complete!${NC}"
echo

echo "Next steps:"
echo "1. Create PVCs using 'ceph-rbd' or 'ceph-cephfs' StorageClass"
echo "2. See docs/CEPH_MICROK8S.md for examples"
echo "3. Monitor cluster: ceph -w"
echo "4. Check Kubernetes: kubectl get pvc,pv"
