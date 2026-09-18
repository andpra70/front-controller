#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ ! -f .env ]]; then
    echo "Missing .env file. Continuing with DOMAIN=localhost."
fi

if [[ -f .env ]]; then
    set -a
    . ./.env
    set +a
fi

if docker-compose ps -q | grep -q .; then
    docker-compose down
fi

docker-compose build --no-cache front-controller
docker-compose up -d --force-recreate
echo "Project containers started."
echo "HTTP:        http://${DOMAIN:-localhost}"
echo "Public URL:  https://${DOMAIN:-localhost}"
echo "Local Mongo:  mongodb://localhost:${MONGO_HOST_PORT:-27017}"
echo "Mongo Express: http://localhost:${MONGO_EXPRESS_HOST_PORT:-8081}"
echo "Public NAT required: TCP 80 -> 80, TCP 443 -> 443"
