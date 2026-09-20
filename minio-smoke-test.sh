#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; cd "$SCRIPT_DIR"
[[ -f .env ]] && { set -a; . ./.env; set +a; }
NAME="smoke-$(date +%Y%m%d-%H%M%S)"; KEY="_smoke/$NAME.txt"; CONTENT="minio-smoke-$NAME"
mc_run(){ docker compose run --rm --no-deps --entrypoint /bin/sh minio-init -c "mc alias set local http://minio:9000 \"\$MINIO_ROOT_USER\" \"\$MINIO_ROOT_PASSWORD\" >/dev/null; $1"; }
printf '%s' "$CONTENT" | docker compose run --rm -T --no-deps --entrypoint /bin/sh minio-init -c 'mc alias set local http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null; mc pipe --attr "Content-Type=text/plain;Content-Disposition=attachment%3B%20filename%3Dsmoke.txt" local/public-assets/'"$KEY"
./minio-backup.sh "$NAME"
mc_run "mc rm local/public-assets/$KEY"
./minio-restore.sh "export-minio/$NAME.tar.gz"
RESTORED="$(mc_run "mc cat local/public-assets/$KEY")"; [[ "$RESTORED" == "$CONTENT" ]] || { echo "Smoke test failed."; exit 1; }
mc_run "mc rm local/public-assets/$KEY" >/dev/null
echo "MinIO backup/restore smoke test passed."
