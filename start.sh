#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ ! -f .env ]]; then
    echo "Missing .env file. Continuing with DOMAIN=localhost."
fi

if docker compose ps -q | grep -q .; then
    docker compose down
fi

./scripts.sh

if [[ ! -f certs/live/fullchain.pem || ! -f certs/live/privkey.pem ]]; then
    echo "Missing TLS certificate files in certs/live."
    exit 1
fi

docker compose build --no-cache front-controller
docker compose up -d --force-recreate
echo "Project containers started."
echo "Local HTTP:  http://localhost:55000"
echo "Local HTTPS: https://localhost:55443"
echo "Public NAT required: TCP 80 -> 55000, TCP 443 -> 55443"
