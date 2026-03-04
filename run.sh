#!/bin/bash
set -euo pipefail

REGISTRY="${REGISTRY:-docker.io/andpra70}"
IMAGE_NAME="${IMAGE_NAME:-front-controller}"
TAG="${TAG:-latest}"
CONTAINER_NAME="${CONTAINER_NAME:-front-controller}"
HOST_PORT="${HOST_PORT:-9090}"
CONTAINER_PORT="${CONTAINER_PORT:-80}"
FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${TAG}"

if docker ps -a --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"; then
    docker stop "$CONTAINER_NAME"
    docker rm "$CONTAINER_NAME"
fi

docker pull "$FULL_IMAGE"
docker run -d \
    --name "$CONTAINER_NAME" \
    -p "${HOST_PORT}:${CONTAINER_PORT}" \
    "$FULL_IMAGE"

echo "Container started"
echo "Image: $FULL_IMAGE"
echo "Name: $CONTAINER_NAME"
echo "URL: http://localhost:${HOST_PORT}"
