#!/bin/bash
set -o pipefail

DEVICE="$1"
DEVNAME=$(basename "$DEVICE")
CURRENT_FSID="$2"

# Method 1: Check active systemd services and their ceph_fsid
ACTIVE_OSDS=$(systemctl list-units --type=service --no-pager --no-legend --all | grep -oE 'ceph-osd@[0-9]+' || true)
for svc in $ACTIVE_OSDS; do
  id=${svc#ceph-osd@}
  state=$(systemctl show "$svc" -p ActiveState --value)
  if [ "$state" = "active" ]; then
    fsid_file="/var/lib/ceph/osd/ceph-$id/ceph_fsid"
    if [ -f "$fsid_file" ]; then
      osd_fsid=$(cat "$fsid_file" 2>/dev/null | tr -d ' ')
      if [ "$osd_fsid" = "$CURRENT_FSID" ]; then
        echo "OSD_ACTIVE"
        exit 0
      fi
    fi
  fi
done

# Method 2: Check ceph-volume LVM metadata (fallback)
if ceph-volume lvm list 2>/dev/null | grep -q "$DEVNAME"
then
  OSD_FSID=$(ceph-volume lvm list 2>/dev/null | awk -v dev="$DEVNAME" '
    /osd fsid/ { fsid=$3 }
    /devices/  { if ($0 ~ dev) print fsid }
  ' | head -n1)

  if [ "$OSD_FSID" = "$CURRENT_FSID" ]; then
    echo "OSD_EXISTS"
    exit 0
  else
    echo "OSD_STALE"
    exit 0
  fi
fi

# No metadata found at all
echo "OSD_NOT_EXISTS"
