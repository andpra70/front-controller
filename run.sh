#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
mkdir -p data/mongo data/minio data/redis export-mongo export-minio

REGISTRY="${REGISTRY:-docker.io/andpra70}"
IMAGE_NAME="${IMAGE_NAME:-front-controller}"
TAG="${TAG:-latest}"
FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${TAG}"
STACK_NAME="${STACK_NAME:-front-controller}"

if [[ ! -f .env ]]; then
    echo "Missing .env file. Continuing with DOMAIN=localhost."
fi

DOMAIN="${DOMAIN:-localhost}"
if [[ -f .env ]]; then
    set -a
    . ./.env
    set +a
    DOMAIN="${DOMAIN:-localhost}"
fi

docker compose -p "$STACK_NAME" pull
if docker compose -p "$STACK_NAME" ps -q | grep -q .; then
    docker compose -p "$STACK_NAME" down
fi

docker compose -p "$STACK_NAME" up -d --force-recreate --pull never --remove-orphans

echo "Stack started"
echo "Front controller image: $FULL_IMAGE"
echo "HTTP URL:  http://${DOMAIN}"
echo "Local Mongo:  mongodb://localhost:${MONGO_HOST_PORT:-27017}"
echo "Mongo Express: http://localhost:${MONGO_EXPRESS_HOST_PORT:-8081}"
echo "HTTPS URL: https://${DOMAIN}"
echo "Public NAT required: TCP 80 -> 80, TCP 443 -> 443"
