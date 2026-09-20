#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
mkdir -p data/mongo data/minio data/redis export-mongo export-minio

if [[ ! -f .env ]]; then
    echo "Missing .env file. Continuing with DOMAIN=localhost."
fi

if docker compose ps -q | grep -q .; then
    docker compose down
fi

docker compose up --build
