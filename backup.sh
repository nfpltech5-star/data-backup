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
STAGE="/tmp/backup-stage"
TS_FILE=$(date +"%d-%m-%Y %H:%M")

echo "Starting backup to //$SMB_SERVER/$SMB_SHARE/$REMOTE_PATH"
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
# Prepare staging directory (hardlinks)
# =====================================
echo "Preparing files..."
rm -rf "$STAGE"

cd "$SOURCE"
find . -type f \
  ! -path "*/temp/*" \
  ! -name "*.sqlite" \
  ! -name "*.sqlite-wal" \
  ! -name "*.sqlite-shm" \
| while IFS= read -r FILE; do
  mkdir -p "$STAGE/$(dirname "$FILE")"
  ln "${SOURCE}/${FILE#./}" "$STAGE/${FILE#./}" 2>/dev/null || \
  cp "${SOURCE}/${FILE#./}" "$STAGE/${FILE#./}"
done
cd - >/dev/null

FILE_COUNT=$(find "$STAGE" -type f | wc -l)
echo "Uploading ${FILE_COUNT} files..."

# =====================================
# Create remote directory
# =====================================
smbclient //${SMB_SERVER}/${SMB_SHARE} \
  -U ${SMB_USER}%${SMB_PASS} \
  --option='client min protocol=SMB2' \
  --option='client max protocol=SMB3' \
  --timeout=1200 \
  -c "mkdir ${REMOTE_PATH}" 2>/dev/null || true

# =====================================
# Recursive upload (single connection)
# =====================================
smbclient //${SMB_SERVER}/${SMB_SHARE} \
  -U ${SMB_USER}%${SMB_PASS} \
  --option='client min protocol=SMB2' \
  --option='client max protocol=SMB3' \
  --timeout=1200 \
  -c "recurse ON; prompt OFF; cd ${REMOTE_PATH}; lcd ${STAGE}; mput *"

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
rm -rf "$STAGE"
rm -f /tmp/lastbackup.txt
find "$SOURCE" -type f -name "*.sqlite.backup" -delete

echo "--------------------------------------"
echo "Backup completed at ${TS_FILE}"