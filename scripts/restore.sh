#!/bin/bash

set -e

# ----------------------------
# Variables
# ----------------------------
RESTORE_TARGET="/Dokploy/data"
MOUNT_POINT="/mnt/DokployBackup"
SMB_SHARE="//192.168.1.5/DokployBackup"
BACKUP_FILE="dokploy_backup.tar.gz"
SERVER_BACKUP_PATH="$MOUNT_POINT/backups/$BACKUP_FILE"

# ----------------------------
# Safety Check
# ----------------------------
if [ "$RESTORE_TARGET" = "/" ]; then
    echo "Restore target cannot be /"
    exit 1
fi

# ----------------------------
# Prepare mount point
# ----------------------------
mkdir -p "$MOUNT_POINT"

# ----------------------------
# Mount with retries
# ----------------------------
MOUNT_SUCCESS=false

for i in {1..3}; do
    echo "Mount attempt $i..."

    if mount -t cifs "$SMB_SHARE" "$MOUNT_POINT" -o credentials=/root/.smbcredentials,vers=3.0; then
        echo "Mount successful."
        MOUNT_SUCCESS=true
        break
    else
        echo "Mount failed. Retrying in 5 seconds..."
        sleep 5
    fi
done

if [ "$MOUNT_SUCCESS" = false ]; then
    echo "Mount failed. Restore aborted."
    exit 1
fi

# ----------------------------
# Verify backup exists
# ----------------------------
if [ ! -f "$SERVER_BACKUP_PATH" ]; then
    echo "Backup file not found on NAS: $SERVER_BACKUP_PATH"
    umount "$MOUNT_POINT"
    exit 1
fi

echo "Backup file located."

# ----------------------------
# Stop Docker
# ----------------------------
echo "Stopping Docker..."
systemctl stop docker docker.socket containerd 2>/dev/null || true

# ----------------------------
# Clean existing data
# ----------------------------
echo "Cleaning existing Dokploy data..."

if [ -d "$RESTORE_TARGET" ]; then
    rm -rf "$RESTORE_TARGET"
fi

mkdir -p "$RESTORE_TARGET"

# ----------------------------
# Restore archive
# ----------------------------
echo "Restoring backup..."

tar -xzf "$SERVER_BACKUP_PATH" -C /Dokploy

echo "Restore completed."

# ----------------------------
# Start Docker
# ----------------------------
echo "Starting Docker..."
systemctl start docker

# ----------------------------
# Unmount NAS
# ----------------------------
if mountpoint -q "$MOUNT_POINT"; then
    echo "Unmounting NAS..."
    umount "$MOUNT_POINT"
fi

echo "Restore process finished successfully."