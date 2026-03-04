#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

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

mkdir -p certs/live

openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout "$SCRIPT_DIR/certs/live/privkey.pem" \
    -out "$SCRIPT_DIR/certs/live/fullchain.pem" \
    -days 365 \
    -subj "/CN=$DOMAIN" \
    -addext "subjectAltName=DNS:$DOMAIN,DNS:localhost,IP:127.0.0.1"

echo "Self-signed certificate generated for $DOMAIN"
