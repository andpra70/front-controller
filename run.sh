#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

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

if docker-compose -p "$STACK_NAME" ps -q | grep -q .; then
    docker-compose -p "$STACK_NAME" down
fi

./scripts.sh

if [[ ! -f certs/live/fullchain.pem || ! -f certs/live/privkey.pem ]]; then
    echo "Missing TLS certificate files in certs/live."
    exit 1
fi

docker-compose -p "$STACK_NAME" pull app-index galleria minicms watermarks catalogo-opere crawler calendario || true
docker-compose -p "$STACK_NAME" build --no-cache front-controller
docker-compose -p "$STACK_NAME" up -d --force-recreate

echo "Stack started"
echo "Front controller image: $FULL_IMAGE"
echo "Local HTTP:  http://localhost:55000"
echo "Local HTTPS: https://localhost:55443"
echo "HTTPS URL: https://${DOMAIN}:55443"
echo "Public NAT required: TCP 80 -> 55000, TCP 443 -> 55443"
