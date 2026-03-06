#!/bin/bash

set -e

# ----------------------------
# Variables
# ----------------------------
SOURCE="/Dokploy/data"
EXCLUDE="/Dokploy/data/n8n-test"
BACKUP_DIR="/Dokploy/backups"
BACKUP_NAME="dokploy_backup.tar.gz"
MOUNT_POINT="/mnt/DokployBackup"
SMB_SHARE="//192.168.1.5/DokployBackup"
TIMESTAMP=$(date "+%d-%m-%Y %H:%M")

# ----------------------------
# Stop Docker services
# ----------------------------
echo "Stopping Docker..."
systemctl stop docker docker.socket containerd 2>/dev/null || true

# ----------------------------
# Ensure backup folder exists
# ----------------------------
mkdir -p "$BACKUP_DIR"

# ----------------------------
# Create backup
# ----------------------------

echo "Creating backup archive..."

tar -czf "$BACKUP_DIR/$BACKUP_NAME" \
--exclude="$EXCLUDE" \
--checkpoint=1000 \
--checkpoint-action=echo="Processed %u checkpoints" \
-C /Dokploy data

echo "Backup created: $BACKUP_DIR/$BACKUP_NAME"


# ----------------------------
# Start Docker again
# ----------------------------
echo "Starting Docker..."
systemctl start docker

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

# ----------------------------
# Copy backup if mount succeeded
# ----------------------------
if [ "$MOUNT_SUCCESS" = true ]; then
    echo "Copying backup to NAS..."

    mkdir -p "$MOUNT_POINT/backups"
    cp "$BACKUP_DIR/$BACKUP_NAME" "$MOUNT_POINT/backups/"

    echo "Backup copied to $MOUNT_POINT/backups"

    # Create last backup timestamp file on server
    echo "$TIMESTAMP" > "$MOUNT_POINT/backups/lastbackup.txt"

    echo "lastbackup.txt updated with time $TIMESTAMP"
else
    echo "Mount failed after 3 attempts. Backup remains local."
fi

echo "Backup process completed."

# ----------------------------
# Unmount NAS
# ----------------------------

if mountpoint -q "$MOUNT_POINT"; then
    echo "Unmounting NAS..."
    umount "$MOUNT_POINT"
fi