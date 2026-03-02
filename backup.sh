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

# --- Start upload in background ---
smbclient //${SMB_SERVER}/${SMB_SHARE} \
  -U ${SMB_USER}%${SMB_PASS} \
  --option='client min protocol=SMB2' \
  --option='client max protocol=SMB3' \
  --timeout=1200 \
  -c "put ${ARCHIVE_PATH} ${REMOTE_PATH}/${ARCHIVE_NAME}" &
UPLOAD_PID=$!

# --- Wait briefly for smbclient to open the file ---
sleep 2

# --- Find the fd that points to our archive ---
ARCHIVE_FD=""
for fd in /proc/$UPLOAD_PID/fd/*; do
  target=$(readlink "$fd" 2>/dev/null || true)
  if [ "$target" = "$ARCHIVE_PATH" ]; then
    ARCHIVE_FD=$(basename "$fd")
    break
  fi
done

# --- Progress monitor (every 3 sec) ---
set +e
while kill -0 $UPLOAD_PID 2>/dev/null; do
  SENT=0
  if [ -n "$ARCHIVE_FD" ] && [ -f "/proc/$UPLOAD_PID/fdinfo/$ARCHIVE_FD" ]; then
    SENT=$(awk '/^pos:/ {print $2}' /proc/$UPLOAD_PID/fdinfo/$ARCHIVE_FD 2>/dev/null || echo 0)
  fi

  [ -z "$SENT" ] && SENT=0
  PCT=$(awk "BEGIN {p=int($SENT*100/$TOTAL_BYTES); if(p>100) p=100; print p}")
  SENT_MB=$(awk "BEGIN {printf \"%.1f\", $SENT/1048576}")

  # Build bar (20 chars wide)
  FILLED=$((PCT / 5))
  EMPTY=$((20 - FILLED))
  BAR=$(printf '%0.s█' $(seq 1 $FILLED 2>/dev/null) 2>/dev/null || true)
  SPC=$(printf '%0.s░' $(seq 1 $EMPTY  2>/dev/null) 2>/dev/null || true)

  echo "  [${BAR}${SPC}] ${PCT}%  (${SENT_MB} / ${TOTAL_MB} MB)"
  sleep 3
done

# --- Wait for upload to finish & check exit code ---
wait $UPLOAD_PID
UPLOAD_RC=$?
set -e
echo "  [████████████████████] 100%  (${TOTAL_MB} / ${TOTAL_MB} MB)"
echo "Upload complete."

if [ $UPLOAD_RC -ne 0 ]; then
  echo "ERROR: Upload failed with exit code $UPLOAD_RC"
  exit $UPLOAD_RC
fi

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