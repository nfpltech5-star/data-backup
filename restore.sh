#!/bin/bash
set -e

# ================================
# Validate ENV
# ================================
if [ -z "$REMOTE_PATH" ]; then
  echo "❌ Missing REMOTE_PATH environment variable."
  exit 1
fi

DEST="/dokploy-data/"
MOUNT_POINT="/mnt/backup"
SOURCE="${MOUNT_POINT}/${REMOTE_PATH}"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║       DOKPLOY RESTORE (rsync)            ║"
echo "╠══════════════════════════════════════════╣"
echo "║  Source : $SOURCE                          "
echo "║  Path   : $REMOTE_PATH                    "
echo "╚══════════════════════════════════════════╝"
echo ""

# =====================================
# Verify mount & source
# =====================================
if ! mountpoint -q "$MOUNT_POINT" 2>/dev/null && [ ! -d "$MOUNT_POINT" ]; then
  echo "❌ SMB share not mounted at $MOUNT_POINT"
  echo "   Check your docker-compose volume configuration."
  exit 1
fi

if [ ! -d "$SOURCE" ]; then
  echo "❌ Remote backup path not found: $SOURCE"
  exit 1
fi

# =====================================
# Rsync restore with progress
# =====================================
echo "🔄 Restoring from backup..."
echo "----------------------------------------------"

rsync -ah --delete \
    --info=progress2 \
    --no-inc-recursive \
    "$SOURCE/" \
    "$DEST"

echo "----------------------------------------------"

# =====================================
# Restore SQLite backups
# =====================================
echo "🗄 Restoring SQLite files..."
find "$DEST" -type f -name "*.sqlite.backup" | while read -r SNAP; do
  echo "   → Restored: ${SNAP#$DEST}"
  mv "$SNAP" "${SNAP%.backup}"
done

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║  ✅ Restore completed successfully        "
echo "║  📍 Data restored to $DEST                "
echo "╚══════════════════════════════════════════╝"
echo ""