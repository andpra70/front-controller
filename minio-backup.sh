#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; cd "$SCRIPT_DIR"
[[ -f .env ]] && { set -a; . ./.env; set +a; }
BACKUP_NAME="${1:-minio-$(date +%Y%m%d-%H%M%S)}"; EXPORT_DIR="${MINIO_EXPORT_DIR:-$SCRIPT_DIR/export-minio}"
ARCHIVE="$EXPORT_DIR/$BACKUP_NAME.tar.gz"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$EXPORT_DIR" "$TMP/objects"
docker compose ps --services --filter status=running | grep -qx minio || { echo "MinIO is not running."; exit 1; }
docker compose run --rm --no-deps --entrypoint /bin/sh -v "$TMP:/backup" minio-init -c '
  set -eu
  mc alias set local http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null
  mc stat local/public-assets >/dev/null
  mc mirror --preserve local/public-assets /backup/objects
  mc anonymous get-json local/public-assets > /backup/policy.json
  mc version info local/public-assets > /backup/versioning.txt 2>/dev/null || true
  mc du --json local/public-assets > /backup/usage.json
'
OBJECTS="$(find "$TMP/objects" -type f | wc -l | tr -d ' ')"; BYTES="$(du -sb "$TMP/objects" | awk '{print $1}')"
cat > "$TMP/manifest.json" <<EOF
{"formatVersion":1,"createdAt":"$(date -u +%FT%TZ)","bucket":"public-assets","objects":$OBJECTS,"bytes":$BYTES}
EOF
tar -C "$TMP" -czf "$ARCHIVE" manifest.json policy.json versioning.txt usage.json objects
sha256sum "$ARCHIVE" > "$ARCHIVE.sha256"
echo "MinIO backup created: $ARCHIVE ($OBJECTS objects, $BYTES bytes)"
