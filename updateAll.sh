#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

mapfile -t SERVICES < <(docker-compose config --services)

if [[ ${#SERVICES[@]} -eq 0 ]]; then
    echo "No services found in docker-compose configuration."
    exit 1
fi

FAILED_SERVICES=()

for SERVICE_NAME in "${SERVICES[@]}"; do
    echo
    echo "=== Updating ${SERVICE_NAME} ==="

    if ! "$SCRIPT_DIR/update-service.sh" "$SERVICE_NAME"; then
        FAILED_SERVICES+=("$SERVICE_NAME")
        echo "Update failed for: ${SERVICE_NAME}"
    fi
done

echo
if [[ ${#FAILED_SERVICES[@]} -gt 0 ]]; then
    echo "Update completed with errors."
    echo "Failed services: ${FAILED_SERVICES[*]}"
    exit 1
fi

echo "All services updated successfully."
