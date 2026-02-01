#!/bin/bash
#
# CSI Staging Path Helper for MicroK8s
# This script monitors kubelet's attempt to stage CSI volumes and pre-creates
# the required subdirectories to work around a MicroK8s/kubelet limitation.
#
# The issue: Kubelet should create volume-specific staging subdirectories 
# before calling NodeStageVolume, but MicroK8s doesn't. This helper watches 
# kubelet logs and creates the directories on-demand.
#

set -e

STAGING_BASE="/var/snap/microk8s/common/var/lib/kubelet/plugins/kubernetes.io/csi/rbd.csi.ceph.com"
CSI_NODEPLUGIN_POD="ceph-csi-rbd-nodeplugin"
CSI_NAMESPACE="ceph-csi-rbd"
LOG_FILE="/tmp/csi-staging-helper.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

get_node() {
    hostname
}

check_csi_plugin_pod() {
    local node=$1
    kubectl get pods -n "$CSI_NAMESPACE" -o wide | grep "nodeplugin" | grep "$node" > /dev/null
}

get_csi_pod_on_node() {
    local node=$1
    kubectl get pods -n "$CSI_NAMESPACE" -o wide | grep "nodeplugin" | grep "$node" | awk '{print $1}'
}

# Monitor kubelet logs for failing NodeStageVolume calls and extract volume hashes
monitor_and_create_staging_dirs() {
    local node=$(get_node)
    log "Starting CSI staging helper on node: $node"
    
    if ! command -v kubectl &> /dev/null; then
        log "ERROR: kubectl not found in PATH"
        return 1
    fi
    
    if ! check_csi_plugin_pod "$node"; then
        log "WARNING: CSI nodeplugin pod not found on $node"
        return 1
    fi
    
    local csi_pod=$(get_csi_pod_on_node "$node")
    log "CSI nodeplugin pod on $node: $csi_pod"
    
    # Monitor kubelet logs and watch for NodeStageVolume failures
    log "Monitoring kubelet logs for missing staging paths..."
    
    # Use journalctl to watch kubelet logs in real-time
    # Extract volume hash from error messages and create directories
    sudo journalctl -u snap.microk8s.kubelet -f 2>/dev/null | while read -r line; do
        if echo "$line" | grep -q "staging path.*does not exist"; then
            # Extract the full staging path from the error
            local staging_path=$(echo "$line" | grep -oP 'staging path \K[^ ]+' | head -1)
            
            if [ -n "$staging_path" ] && [[ $staging_path == *"rbd.csi.ceph.com"* ]]; then
                log "Detected missing staging path: $staging_path"
                
                # Create the directory via the CSI plugin pod (which has proper privileges)
                if kubectl exec -n "$CSI_NAMESPACE" "$csi_pod" -c csi-rbdplugin -- \
                   mkdir -p "$staging_path" 2>/dev/null; then
                    log "${GREEN}✓ Created staging directory: $staging_path${NC}"
                else
                    log "${RED}✗ Failed to create staging directory: $staging_path${NC}"
                fi
            fi
        fi
    done
}

# Alternative: Pre-create expected directories (batch approach)
precreate_common_directories() {
    local node=$(get_node)
    local csi_pod=$(get_csi_pod_on_node "$node")
    
    if [ -z "$csi_pod" ]; then
        log "ERROR: Cannot find CSI nodeplugin pod on $node"
        return 1
    fi
    
    log "Pre-creating common CSI staging directories on $node..."
    
    # Create the parent directory structure
    kubectl exec -n "$CSI_NAMESPACE" "$csi_pod" -c csi-rbdplugin -- \
        mkdir -p /var/lib/kubelet/plugins/kubernetes.io/csi/rbd.csi.ceph.com
    
    log "${GREEN}✓ Parent directories created${NC}"
}

# Main execution
main() {
    log "===== CSI Staging Helper Started ====="
    
    # Check if running as root (needed for journalctl)
    if [ "$EUID" -ne 0 ]; then
        log "ERROR: This script must be run as root"
        exit 1
    fi
    
    # First, precreate common directories
    if precreate_common_directories; then
        log "Initial directory creation successful"
    else
        log "WARNING: Failed to precreate directories, will attempt on-demand creation"
    fi
    
    # Then monitor and create on-demand
    monitor_and_create_staging_dirs
}

main "$@"
