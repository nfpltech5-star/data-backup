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
# Prepare smbclient batch commands
# =====================================
echo "Preparing file list..."
CMD_FILE="/tmp/smb_commands.txt"
> "$CMD_FILE"

# Create remote base directory
echo "mkdir ${REMOTE_PATH}" >> "$CMD_FILE"

cd "$SOURCE"

# Create all remote subdirectories (sorted so parents come first)
find . -mindepth 1 -type d \
  ! -path "*/temp/*" \
  | sort | while read -r DIR; do
    echo "mkdir \"${REMOTE_PATH}/${DIR#./}\"" >> "$CMD_FILE"
done

# Queue file uploads (excluding temp, live sqlite)
find . -type f \
  ! -path "*/temp/*" \
  ! -name "*.sqlite" \
  ! -name "*.sqlite-wal" \
  ! -name "*.sqlite-shm" \
| while read -r FILE; do
  echo "put \"${SOURCE}/${FILE#./}\" \"${REMOTE_PATH}/${FILE#./}\"" >> "$CMD_FILE"
done

cd - >/dev/null

FILE_COUNT=$(grep -c '^put ' "$CMD_FILE" || echo 0)
echo "Uploading ${FILE_COUNT} files..."

# =====================================
# Upload via smbclient (single connection)
# =====================================
smbclient //${SMB_SERVER}/${SMB_SHARE} \
  -U ${SMB_USER}%${SMB_PASS} \
  --option='client min protocol=SMB2' \
  --option='client max protocol=SMB3' \
  --timeout=1200 \
  < "$CMD_FILE"

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
rm -f "$CMD_FILE"
rm -f /tmp/lastbackup.txt
find "$SOURCE" -type f -name "*.sqlite.backup" -delete

echo "--------------------------------------"
echo "Backup completed at ${TS_FILE}"