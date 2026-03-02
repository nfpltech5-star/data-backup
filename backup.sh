#!/bin/bash
set -e

# ================================
# Validate ENV
# ================================
if [ -z "$REMOTE_PATH" ]; then
  echo "❌ Missing REMOTE_PATH environment variable."
  exit 1
fi

SOURCE="/dokploy-data/"
MOUNT_POINT="/mnt/backup"
DEST="${MOUNT_POINT}/${REMOTE_PATH}"
TS_FILE=$(date +"%d-%m-%Y %H:%M")

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║        DOKPLOY BACKUP (rsync)            ║"
echo "╠══════════════════════════════════════════╣"
echo "║  Dest   : $DEST                           "
echo "║  Path   : $REMOTE_PATH                    "
echo "╚══════════════════════════════════════════╝"
echo ""

# =====================================
# Verify mount is available
# =====================================
if ! mountpoint -q "$MOUNT_POINT" 2>/dev/null && [ ! -d "$MOUNT_POINT" ]; then
  echo "❌ SMB share not mounted at $MOUNT_POINT"
  echo "   Check your docker-compose volume configuration."
  exit 1
fi

mkdir -p "$DEST"

# =====================================
# Safe SQLite Snapshots
# =====================================
echo "📦 Creating SQLite snapshots..."
SNAPSHOT_COUNT=0
while IFS= read -r DB_PATH; do
  SNAPSHOT="${DB_PATH}.backup"
  echo "   → ${DB_PATH#$SOURCE}"
  sqlite3 "$DB_PATH" ".backup '$SNAPSHOT'" 2>/dev/null || echo "   ⚠ Snapshot failed for ${DB_PATH#$SOURCE}"
  SNAPSHOT_COUNT=$((SNAPSHOT_COUNT + 1))
done < <(find "$SOURCE" -type f -name "*.sqlite" 2>/dev/null)

if [ "$SNAPSHOT_COUNT" -gt 0 ]; then
  echo "   ✅ $SNAPSHOT_COUNT snapshot(s) created"
  sync
  sleep 1
else
  echo "   ℹ No SQLite files found, skipping snapshots."
fi

# =====================================
# Rsync with progress bar
# =====================================
echo ""
echo "🚀 Starting rsync transfer..."
echo "----------------------------------------------"

rsync -ah --delete \
    --info=progress2 \
    --no-inc-recursive \
    --exclude='*.sqlite' \
    --exclude='*.sqlite-wal' \
    --exclude='*.sqlite-shm' \
    --exclude='temp/' \
    --include='*.sqlite.backup' \
    "$SOURCE" \
    "$DEST/"

echo "----------------------------------------------"

# =====================================
# Write timestamp marker
# =====================================
echo "${TS_FILE}" > "${DEST}/lastbackup.txt"

# =====================================
# Cleanup
# =====================================
find "$SOURCE" -type f -name "*.sqlite.backup" -delete 2>/dev/null || true

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║  ✅ Backup completed at ${TS_FILE}        "
echo "║  📍 ${DEST}                                "
echo "╚══════════════════════════════════════════╝"
echo ""