#!/bin/bash
set -e

if [ -z "$SMB_SERVER" ] || [ -z "$SMB_SHARE" ] || \
   [ -z "$REMOTE_PATH" ] || [ -z "$SMB_USER" ] || [ -z "$SMB_PASS" ]; then
  echo "Missing required environment variables."
  exit 1
fi

DEST="/dokploy-data"

echo "Starting restore from //$SMB_SERVER/$SMB_SHARE/$REMOTE_PATH"
echo "--------------------------------------"

echo "Clearing destination..."
rm -rf ${DEST:?}/*

echo "Downloading files..."
mkdir -p "$DEST"

smbclient //${SMB_SERVER}/${SMB_SHARE} \
  -U ${SMB_USER}%${SMB_PASS} \
  --option='client min protocol=SMB2' \
  --option='client max protocol=SMB3' \
  --timeout=1200 \
  -c "recurse ON; prompt OFF; cd ${REMOTE_PATH}; lcd ${DEST}; mget *"

# Restore SQLite backups
echo "Restoring SQLite files..."
find "$DEST" -type f -name "*.sqlite.backup" | while read -r SNAP; do
  mv "$SNAP" "${SNAP%.backup}"
done

echo "--------------------------------------"
echo "Restore completed successfully."