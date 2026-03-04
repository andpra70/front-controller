#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

MONGO_ROOT_USERNAME="${MONGO_ROOT_USERNAME:-root}"
MONGO_ROOT_PASSWORD="${MONGO_ROOT_PASSWORD:-rootpass}"
TEST_DB="${TEST_DB:-smoke_test_db}"
TEST_COLLECTION="${TEST_COLLECTION:-smoke_test_collection}"
TEST_MARKER="smoke-$(date +%Y%m%d-%H%M%S)"
BACKUP_NAME="smoke-test-${TEST_MARKER}"

if [[ -f .env ]]; then
    set -a
    . ./.env
    set +a
    MONGO_ROOT_USERNAME="${MONGO_ROOT_USERNAME:-root}"
    MONGO_ROOT_PASSWORD="${MONGO_ROOT_PASSWORD:-rootpass}"
fi

mongo_eval() {
    docker-compose exec -T mongo mongosh --quiet \
        --username "$MONGO_ROOT_USERNAME" \
        --password "$MONGO_ROOT_PASSWORD" \
        --authenticationDatabase admin \
        --eval "$1"
}

echo "Inserting smoke test document..."
mongo_eval "db.getSiblingDB('$TEST_DB').getCollection('$TEST_COLLECTION').insertOne({marker: '$TEST_MARKER', createdAt: new Date()})"

echo "Running backup..."
./mongo-backup.sh "$BACKUP_NAME"

echo "Dropping smoke test database..."
mongo_eval "db.getSiblingDB('$TEST_DB').dropDatabase()"

COUNT_AFTER_DROP="$(mongo_eval "db.getSiblingDB('$TEST_DB').getCollection('$TEST_COLLECTION').countDocuments({marker: '$TEST_MARKER'})" | tr -d '\r')"
if [[ "$COUNT_AFTER_DROP" != "0" ]]; then
    echo "Smoke test failed: document still present after drop."
    exit 1
fi

echo "Running restore..."
./mongo-restore.sh "export-mongo/${BACKUP_NAME}.archive.gz"

COUNT_AFTER_RESTORE="$(mongo_eval "db.getSiblingDB('$TEST_DB').getCollection('$TEST_COLLECTION').countDocuments({marker: '$TEST_MARKER'})" | tr -d '\r')"
if [[ "$COUNT_AFTER_RESTORE" != "1" ]]; then
    echo "Smoke test failed: expected restored document count 1, found $COUNT_AFTER_RESTORE."
    exit 1
fi

echo "Cleaning up smoke test data..."
# mongo_eval "db.getSiblingDB('$TEST_DB').dropDatabase()"

echo "Mongo smoke test passed."
