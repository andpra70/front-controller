#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <service-name>"
    exit 1
fi

SERVICE_NAME="$1"

if ! docker compose config --services | grep -Fxq "$SERVICE_NAME"; then
    echo "Unknown service: $SERVICE_NAME"
    exit 1
fi

echo "Pulling latest image for: $SERVICE_NAME"
if ! docker compose pull "$SERVICE_NAME"; then
    echo "Pull unavailable for ${SERVICE_NAME}; continuing with its local build configuration."
fi

echo "Building service when a build context is configured: $SERVICE_NAME"
docker compose build --pull "$SERVICE_NAME"

echo "Starting service: $SERVICE_NAME"
docker compose up -d --no-deps --force-recreate --pull never "$SERVICE_NAME"

echo "Service updated: $SERVICE_NAME"
