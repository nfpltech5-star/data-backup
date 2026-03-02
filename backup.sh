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
TOTAL_BYTES=$(stat -c%s "$ARCHIVE_PATH" 2>/dev/null || stat -f%z "$ARCHIVE_PATH")
TOTAL_MB=$(awk "BEGIN {printf \"%.1f\", $TOTAL_BYTES/1048576}")
echo "Uploading archive... (${TOTAL_MB} MB)"

smbclient //${SMB_SERVER}/${SMB_SHARE} \
  -U ${SMB_USER}%${SMB_PASS} \
  --option='client min protocol=SMB2' \
  --option='client max protocol=SMB3' \
  --timeout=1200 \
  -c "mkdir ${REMOTE_PATH}" >/dev/null 2>&1 || true

# --- Background progress monitor (every 3 sec) ---
(
  while true; do
    sleep 3

    REMOTE_SIZE=$(smbclient //${SMB_SERVER}/${SMB_SHARE} \
      -U ${SMB_USER}%${SMB_PASS} \
      --option='client min protocol=SMB2' \
      --option='client max protocol=SMB3' \
      --timeout=30 \
      -c "ls ${REMOTE_PATH}/${ARCHIVE_NAME}" 2>/dev/null \
      | grep -i "$ARCHIVE_NAME" \
      | awk '{for(i=1;i<=NF;i++){if($i ~ /^[0-9]+$/){print $i; exit}}}')

    [ -z "$REMOTE_SIZE" ] && REMOTE_SIZE=0

    PCT=$(awk "BEGIN {p=int($REMOTE_SIZE*100/$TOTAL_BYTES); if(p>100) p=100; print p}")
    UPLOADED_MB=$(awk "BEGIN {printf \"%.1f\", $REMOTE_SIZE/1048576}")

    # Build bar (20 chars wide)
    FILLED=$((PCT / 5))
    EMPTY=$((20 - FILLED))
    BAR=$(printf '%0.s█' $(seq 1 $FILLED 2>/dev/null) 2>/dev/null || true)
    SPC=$(printf '%0.s░' $(seq 1 $EMPTY  2>/dev/null) 2>/dev/null || true)

    echo "  [$BAR$SPC] ${PCT}%  (${UPLOADED_MB} / ${TOTAL_MB} MB)"
  done
) &
PROGRESS_PID=$!

# --- Actual upload ---
smbclient //${SMB_SERVER}/${SMB_SHARE} \
  -U ${SMB_USER}%${SMB_PASS} \
  --option='client min protocol=SMB2' \
  --option='client max protocol=SMB3' \
  --timeout=1200 \
  -c "put ${ARCHIVE_PATH} ${REMOTE_PATH}/${ARCHIVE_NAME}"

# --- Stop progress monitor ---
kill $PROGRESS_PID 2>/dev/null || true
wait $PROGRESS_PID 2>/dev/null || true
echo "  [████████████████████] 100%  (${TOTAL_MB} / ${TOTAL_MB} MB)"
echo "Upload complete."

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