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
if docker compose pull "$SERVICE_NAME"; then
    echo "Remote image ready: $SERVICE_NAME"
else
    echo "Pull unavailable for ${SERVICE_NAME}; checking its local build configuration."

    if ! command -v jq >/dev/null 2>&1; then
        echo "Cannot inspect the local build configuration: jq is not installed." >&2
        exit 1
    fi

    COMPOSE_CONFIG="$(docker compose config --format json)"
    BUILD_CONTEXT="$(jq -r --arg service "$SERVICE_NAME" '.services[$service].build.context // empty' <<<"$COMPOSE_CONFIG")"
    DOCKERFILE="$(jq -r --arg service "$SERVICE_NAME" '.services[$service].build.dockerfile // "Dockerfile"' <<<"$COMPOSE_CONFIG")"

    if [[ -z "$BUILD_CONTEXT" ]]; then
        echo "No remote image and no local build configured for: $SERVICE_NAME" >&2
        exit 1
    fi

    if [[ ! -f "$BUILD_CONTEXT/$DOCKERFILE" ]]; then
        echo "Local build unavailable: $BUILD_CONTEXT/$DOCKERFILE does not exist." >&2
        echo "On production, deploy the registry image or install the application sources." >&2
        exit 1
    fi

    echo "Building local fallback: $SERVICE_NAME"
    docker compose build --pull "$SERVICE_NAME"
fi

echo "Starting service: $SERVICE_NAME"
docker compose up -d --no-deps --force-recreate --pull never "$SERVICE_NAME"

echo "Service updated: $SERVICE_NAME"
