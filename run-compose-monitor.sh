#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

if ! docker compose version >/dev/null 2>&1; then
    echo "Docker Compose V2 not found. Install the 'docker compose' plugin." >&2
    exit 1
fi

if command -v node >/dev/null 2>&1; then
    exec node ./srrc/compose-monitor.js
fi

if command -v nodejs >/dev/null 2>&1; then
    exec nodejs ./srrc/compose-monitor.js
fi

echo "Node.js runtime not found. Install 'node' or 'nodejs' to run the compose monitor." >&2
exit 1
