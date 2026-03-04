#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

REGISTRY="${REGISTRY:-docker.io/andpra70}"
IMAGE_NAME="${IMAGE_NAME:-front-controller}"
TAG="${TAG:-latest}"
FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${TAG}"

if [[ ! -f .env ]]; then
    echo "Missing .env file. Continuing with DOMAIN=localhost."
fi

./scripts.sh

docker build -t "$FULL_IMAGE" .
docker push "$FULL_IMAGE"

echo "Image published: $FULL_IMAGE"
