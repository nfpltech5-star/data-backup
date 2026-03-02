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

SMB_COMMON="-U ${SMB_USER}%${SMB_PASS} \
  --option='client min protocol=SMB2' \
  --option='client max protocol=SMB3' \
  --timeout=1200"

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
# Collect files to upload
# =====================================
echo "Scanning files..."
FILE_LIST="/tmp/backup_filelist.txt"

cd "$SOURCE"
find . -type f \
  ! -path "*/temp/*" \
  ! -name "*.sqlite" \
  ! -name "*.sqlite-wal" \
  ! -name "*.sqlite-shm" \
  > "$FILE_LIST"
cd - >/dev/null

FILE_COUNT=$(wc -l < "$FILE_LIST")
echo "Found ${FILE_COUNT} files to upload."

# =====================================
# Create remote base directory
# =====================================
smbclient //${SMB_SERVER}/${SMB_SHARE} \
  -U ${SMB_USER}%${SMB_PASS} \
  --option='client min protocol=SMB2' \
  --option='client max protocol=SMB3' \
  --timeout=1200 \
  -c "mkdir ${REMOTE_PATH}" 2>/dev/null || true

# =====================================
# Collect unique directories & create them
# =====================================
echo "Creating remote directories..."

DIR_LIST=$(while IFS= read -r FILE; do
  dirname "$FILE"
done < "$FILE_LIST" | sort -u)

while IFS= read -r DIR; do
  # Build path components and mkdir each level
  RDIR="${REMOTE_PATH}"
  IFS='/' read -ra PARTS <<< "${DIR#./}"
  for PART in "${PARTS[@]}"; do
    [ -z "$PART" ] && continue
    RDIR="${RDIR}/${PART}"
    smbclient //${SMB_SERVER}/${SMB_SHARE} \
      -U ${SMB_USER}%${SMB_PASS} \
      --option='client min protocol=SMB2' \
      --option='client max protocol=SMB3' \
      --timeout=1200 \
      -c "mkdir ${RDIR}" 2>/dev/null || true
  done
done <<< "$DIR_LIST"

# =====================================
# Upload files one by one
# =====================================
echo "Uploading files..."
COUNT=0
FAILED=0

while IFS= read -r FILE; do
  REL="${FILE#./}"
  COUNT=$((COUNT + 1))
  FSIZE=$(stat -c%s "${SOURCE}/${REL}" 2>/dev/null || echo 0)
  echo "[${COUNT}/${FILE_COUNT}] ${REL} ($(numfmt --to=iec ${FSIZE}))"

  if ! pv -f "${SOURCE}/${REL}" | smbclient //${SMB_SERVER}/${SMB_SHARE} \
    -U ${SMB_USER}%${SMB_PASS} \
    --option='client min protocol=SMB2' \
    --option='client max protocol=SMB3' \
    --timeout=1200 \
    -c "put - ${REMOTE_PATH}/${REL}" 2>&1; then
    echo "⚠ Failed: ${REL}"
    FAILED=$((FAILED + 1))
  fi
done < "$FILE_LIST"

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
rm -f "$FILE_LIST"
rm -f /tmp/lastbackup.txt
find "$SOURCE" -type f -name "*.sqlite.backup" -delete

echo "--------------------------------------"
if [ "$FAILED" -gt 0 ]; then
  echo "⚠ Backup completed with ${FAILED} failed file(s) at ${TS_FILE}"
  exit 1
else
  echo "✅ Backup completed at ${TS_FILE} — ${FILE_COUNT} files uploaded"
fi