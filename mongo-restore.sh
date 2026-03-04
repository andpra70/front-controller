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
    ARCHIVE_PATH="$(
        find "$EXPORT_DIR" -maxdepth 1 -type f \( -name '*.archive.gz' -o -name '*.archive' \) \
        -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n 1 | awk '{print $2}'
    )"
fi

if [[ -z "${ARCHIVE_PATH:-}" || ! -f "$ARCHIVE_PATH" ]]; then
    echo "Mongo backup archive not found."
    exit 1
fi

RESTORE_ARGS=(
    --username "$MONGO_ROOT_USERNAME"
    --password "$MONGO_ROOT_PASSWORD"
    --authenticationDatabase admin
    --drop
    --archive
)

if [[ "$ARCHIVE_PATH" == *.gz ]]; then
    RESTORE_ARGS+=(--gzip)
fi

echo "Archive content preview:"
cat "$ARCHIVE_PATH" | docker-compose exec -T mongo mongorestore "${RESTORE_ARGS[@]}" --dryRun --verbose

echo "Restoring all databases from archive..."
cat "$ARCHIVE_PATH" | docker-compose exec -T mongo mongorestore "${RESTORE_ARGS[@]}"

echo "Mongo restore completed for all databases from: $ARCHIVE_PATH"
