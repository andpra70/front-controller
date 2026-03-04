#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

EXPORT_DIR="$SCRIPT_DIR/export-mongo"
MONGO_ROOT_USERNAME="${MONGO_ROOT_USERNAME:-root}"
MONGO_ROOT_PASSWORD="${MONGO_ROOT_PASSWORD:-rootpass}"

if [[ -f .env ]]; then
    set -a
    . ./.env
    set +a
    MONGO_ROOT_USERNAME="${MONGO_ROOT_USERNAME:-root}"
    MONGO_ROOT_PASSWORD="${MONGO_ROOT_PASSWORD:-rootpass}"
fi

if [[ $# -gt 0 ]]; then
    ARCHIVE_PATH="$1"
else
    ARCHIVE_PATH="$(ls -1t "$EXPORT_DIR"/*.archive.gz 2>/dev/null | head -n 1 || true)"
fi

if [[ -z "${ARCHIVE_PATH:-}" || ! -f "$ARCHIVE_PATH" ]]; then
    echo "Mongo backup archive not found."
    exit 1
fi

cat "$ARCHIVE_PATH" | docker-compose exec -T mongo mongorestore \
    --username "$MONGO_ROOT_USERNAME" \
    --password "$MONGO_ROOT_PASSWORD" \
    --authenticationDatabase admin \
    --drop \
    --gzip \
    --archive

echo "Mongo restore completed from: $ARCHIVE_PATH"
