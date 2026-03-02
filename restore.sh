#!/bin/bash
set -e

if [ -z "$SMB_SERVER" ] || [ -z "$SMB_SHARE" ] || \
   [ -z "$REMOTE_PATH" ] || [ -z "$SMB_USER" ] || [ -z "$SMB_PASS" ]; then
  echo "Missing required environment variables."
  exit 1
fi

DEST="/dokploy-data"
TMP_DIR="/tmp/dokploy-restore"
mkdir -p "$TMP_DIR"

echo "Starting restore..."
echo "--------------------------------------"

# Find latest archive
LATEST_ARCHIVE=$(
  smbclient //${SMB_SERVER}/${SMB_SHARE} -U ${SMB_USER}%${SMB_PASS} \
    -c "cd ${REMOTE_PATH}; ls" 2>/dev/null \
  | awk '{print $1}' \
  | grep '^dokploy_data_.*\.tar\.gz$' \
  | sort | tail -n 1
)

if [ -z "$LATEST_ARCHIVE" ]; then
  echo "❌ No backup archive found."
  exit 1
fi

echo "Downloading: $LATEST_ARCHIVE"

LOCAL_ARCHIVE="${TMP_DIR}/${LATEST_ARCHIVE}"

smbclient //${SMB_SERVER}/${SMB_SHARE} \
  -U ${SMB_USER}%${SMB_PASS} \
  -c "cd ${REMOTE_PATH}; get ${LATEST_ARCHIVE} ${LOCAL_ARCHIVE}"

echo "Clearing destination..."
rm -rf ${DEST:?}/*

echo "Extracting archive..."
tar -xzf "$LOCAL_ARCHIVE" -C "$DEST"

# Restore SQLite backups
echo "Restoring SQLite files..."
find "$DEST" -type f -name "*.sqlite.backup" | while read -r SNAP; do
  mv "$SNAP" "${SNAP%.backup}"
done

rm -f "$LOCAL_ARCHIVE"
rmdir "$TMP_DIR" >/dev/null 2>&1 || true

echo "--------------------------------------"
echo "Restore completed successfully."