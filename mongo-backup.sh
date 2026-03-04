#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BACKUP_NAME="${1:-mongo-$(date +%Y%m%d-%H%M%S)}"
EXPORT_DIR="$SCRIPT_DIR/export-mongo"
ARCHIVE_PATH="$EXPORT_DIR/${BACKUP_NAME}.archive.gz"
MONGO_ROOT_USERNAME="${MONGO_ROOT_USERNAME:-root}"
MONGO_ROOT_PASSWORD="${MONGO_ROOT_PASSWORD:-rootpass}"

if [[ -f .env ]]; then
    set -a
    . ./.env
    set +a
    MONGO_ROOT_USERNAME="${MONGO_ROOT_USERNAME:-root}"
    MONGO_ROOT_PASSWORD="${MONGO_ROOT_PASSWORD:-rootpass}"
fi

mkdir -p "$EXPORT_DIR"

echo "Inspecting Mongo databases before backup..."
docker-compose exec -T mongo mongosh --quiet \
    --username "$MONGO_ROOT_USERNAME" \
    --password "$MONGO_ROOT_PASSWORD" \
    --authenticationDatabase admin \
    --eval '
        const admin = db.getSiblingDB("admin");
        const dbs = admin.adminCommand({ listDatabases: 1 }).databases
          .filter(dbInfo => !["admin", "config", "local"].includes(dbInfo.name));
        if (dbs.length === 0) {
          print("WARNING: no application databases found.");
        } else {
          dbs.forEach(dbInfo => {
            const database = db.getSiblingDB(dbInfo.name);
            const names = database.getCollectionNames();
            print(`DB ${dbInfo.name}`);
            names.forEach(name => {
              const count = database.getCollection(name).countDocuments({});
              print(`  ${name}: ${count} docs`);
            });
          });
        }
    '

docker-compose exec -T mongo mongodump \
    --username "$MONGO_ROOT_USERNAME" \
    --password "$MONGO_ROOT_PASSWORD" \
    --authenticationDatabase admin \
    --gzip \
    --archive > "$ARCHIVE_PATH"

echo "Mongo backup created for all databases: $ARCHIVE_PATH"
