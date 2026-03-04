#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <service-name>"
    exit 1
fi

SERVICE_NAME="$1"

if ! docker-compose config --services | grep -Fxq "$SERVICE_NAME"; then
    echo "Unknown service: $SERVICE_NAME"
    exit 1
fi

echo "Stopping service: $SERVICE_NAME"
docker-compose stop "$SERVICE_NAME" || true

echo "Removing stopped container for: $SERVICE_NAME"
docker-compose rm -f "$SERVICE_NAME" || true

echo "Pulling latest image for: $SERVICE_NAME"
docker-compose pull "$SERVICE_NAME"

echo "Starting service: $SERVICE_NAME"
docker-compose up -d --remove-orphans "$SERVICE_NAME"

echo "Service updated: $SERVICE_NAME"
