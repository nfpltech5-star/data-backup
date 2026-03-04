#!/bin/bash
set -e

if [ -z "$SMB_SERVER" ] || [ -z "$SMB_SHARE" ] || \
   [ -z "$REMOTE_PATH" ] || [ -z "$SMB_USER" ] || [ -z "$SMB_PASS" ]; then
  echo "Missing required environment variables."
  exit 1
fi

DEST="/dokploy-data"
ARCHIVE_NAME="dokploy-backup.tar.gz"
TMP_DIR="/tmp/dokploy-restore"
LOCAL_ARCHIVE="${TMP_DIR}/${ARCHIVE_NAME}"

mkdir -p "$TMP_DIR"

echo "Starting restore..."
echo "--------------------------------------"

# =====================================
# Download archive
# =====================================
echo "Downloading: ${REMOTE_PATH}/${ARCHIVE_NAME}"

smbclient //${SMB_SERVER}/${SMB_SHARE} \
  -U ${SMB_USER}%${SMB_PASS} \
  --option='client min protocol=SMB2' \
  --option='client max protocol=SMB3' \
  --timeout=1200 \
  -c "cd ${REMOTE_PATH}; get ${ARCHIVE_NAME} ${LOCAL_ARCHIVE}"

# =====================================
# Ensure destination exists with correct ownership
# =====================================
echo "Ensuring destination directory exists: $DEST"
mkdir -p "$DEST"
chown -R 1000:1000 "$DEST"

# =====================================
# Clear & extract
# =====================================
echo "Clearing destination..."
rm -rf ${DEST:?}/*

echo "Extracting archive..."
tar -xzf "$LOCAL_ARCHIVE" -C "$DEST"

# Fix ownership after extraction (n8n runs as node, UID 1000)
echo "Fixing ownership after extraction..."
chown -R 1000:1000 "$DEST"

# =====================================
# Restore SQLite backups
# =====================================
echo "Restoring SQLite files..."
find "$DEST" -type f -name "*.sqlite.backup" | while read -r SNAP; do
  mv "$SNAP" "${SNAP%.backup}"
done

# =====================================
# Cleanup
# =====================================
rm -f "$LOCAL_ARCHIVE"
rmdir "$TMP_DIR" >/dev/null 2>&1 || true

echo "--------------------------------------"
echo "Restore completed successfully."