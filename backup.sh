#!/bin/bash
set -e

# ================================
# Validate ENV
# ================================
if [ -z "$SMB_SERVER" ] || [ -z "$SMB_SHARE" ] || \
   [ -z "$REMOTE_PATH" ] || [ -z "$SMB_USER" ] || [ -z "$SMB_PASS" ]; then
  echo "Missing required environment variables."
  exit 1
fi

SOURCE="/dokploy-data"
TS_FILE=$(date +"%d-%m-%Y %H:%M")
TS_NAME=$(date +"%Y%m%d_%H%M%S")
ARCHIVE_NAME="dokploy_data_${TS_NAME}.tar.gz"
ARCHIVE_PATH="/tmp/${ARCHIVE_NAME}"

echo "Starting TAR backup to //$SMB_SERVER/$SMB_SHARE/$REMOTE_PATH"
echo "--------------------------------------"

# =====================================
# Safe SQLite Snapshots
# =====================================
echo "Creating SQLite snapshots..."
while IFS= read -r DB_PATH; do
  SNAPSHOT="${DB_PATH}.backup"
  echo "Snapshot → ${DB_PATH#$SOURCE/}"
  sqlite3 "$DB_PATH" ".backup '$SNAPSHOT'" 2>/dev/null || echo "⚠ Snapshot failed"
done < <(find "$SOURCE" -type f -name "*.sqlite")

sync
sleep 1

# =====================================
# Create TAR (BusyBox compatible)
# =====================================
echo "Creating archive: ${ARCHIVE_NAME}"

cd "$SOURCE"

# Create file list excluding temp + live sqlite
find . -type f \
  ! -path "*/temp/*" \
  ! -name "*.sqlite" \
  ! -name "*.sqlite-wal" \
  ! -name "*.sqlite-shm" \
  > /tmp/filelist.txt

tar -czf "$ARCHIVE_PATH" -T /tmp/filelist.txt

cd - >/dev/null

# =====================================
# Upload archive
# =====================================
echo "Uploading archive..."

smbclient //${SMB_SERVER}/${SMB_SHARE} \
  -U ${SMB_USER}%${SMB_PASS} \
  --option='client min protocol=SMB2' \
  --option='client max protocol=SMB3' \
  --timeout=1200 \
  -c "mkdir ${REMOTE_PATH}" >/dev/null 2>&1 || true

smbclient //${SMB_SERVER}/${SMB_SHARE} \
  -U ${SMB_USER}%${SMB_PASS} \
  --option='client min protocol=SMB2' \
  --option='client max protocol=SMB3' \
  --timeout=1200 \
  -c "put ${ARCHIVE_PATH} ${REMOTE_PATH}/${ARCHIVE_NAME}"

# Upload timestamp
echo "${TS_FILE}" > /tmp/lastbackup.txt

smbclient //${SMB_SERVER}/${SMB_SHARE} \
  -U ${SMB_USER}%${SMB_PASS} \
  --option='client min protocol=SMB2' \
  --option='client max protocol=SMB3' \
  --timeout=1200 \
  -c "put /tmp/lastbackup.txt ${REMOTE_PATH}/lastbackup.txt" >/dev/null 2>&1 || true

# =====================================
# Cleanup
# =====================================
rm -f /tmp/filelist.txt
rm -f /tmp/lastbackup.txt
rm -f "$ARCHIVE_PATH"
find "$SOURCE" -type f -name "*.sqlite.backup" -delete

echo "--------------------------------------"
echo "Backup completed at ${TS_FILE}"
echo "Archive: ${REMOTE_PATH}/${ARCHIVE_NAME}"