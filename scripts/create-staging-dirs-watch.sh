#!/bin/bash
#
# Staging Directory Auto-Creator for MicroK8s CSI
# Watches kubelet logs and creates volume-specific staging directories on-demand
#

set -e

STAGING_BASE="/var/snap/microk8s/common/var/lib/kubelet/plugins/kubernetes.io/csi/rbd.csi.ceph.com"
NODE_NAME=$(hostname)

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Extract volume hash from kubelet error log
extract_volume_hash() {
    local line="$1"
    # Extract hash from path like: /var/snap/.../rbd.csi.ceph.com/HASH/globalmount
    echo "$line" | grep -oP 'rbd\.csi\.ceph\.com/\K[a-f0-9]{64}' | head -1
}

# Create staging directory for a specific volume
create_staging_dir() {
    local volume_hash="$1"
    local target_dir="${STAGING_BASE}/${volume_hash}/globalmount"
    
    if [ ! -d "$target_dir" ]; then
        log "${YELLOW}Creating staging directory: ${target_dir}${NC}"
        sudo mkdir -p "$target_dir"
        sudo chmod 777 "$target_dir"
        log "${GREEN}✓ Created${NC}"
        return 0
    else
        log "Directory already exists: $target_dir"
        return 1
    fi
}

main() {
    log "Starting staging directory auto-creator for node: $NODE_NAME"
    log "Monitoring kubelet logs for staging path errors..."
    
    # Use journalctl to follow kubelet logs and extract volume hashes
    sudo journalctl -u snap.microk8s.kubelet -f --no-pager 2>/dev/null | while IFS= read -r line; do
        if echo "$line" | grep -q "staging path.*does not exist"; then
            # Extract the volume hash
            local vol_hash=$(extract_volume_hash "$line")
            
            if [ -n "$vol_hash" ]; then
                log "Detected missing staging path for volume: ${vol_hash:0:16}..."
                create_staging_dir "$vol_hash"
            fi
        fi
    done
}

main "$@"
