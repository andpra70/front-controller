#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; cd "$SCRIPT_DIR"
[[ -f .env ]] && { set -a; . ./.env; set +a; }
EXPORT_DIR="${MINIO_EXPORT_DIR:-$SCRIPT_DIR/export-minio}"; MODE="merge"; YES="false"; ARCHIVE=""
for arg in "$@"; do case "$arg" in --replace) MODE="replace";; --yes) YES="true";; *) ARCHIVE="$arg";; esac; done
if [[ -z "$ARCHIVE" ]]; then ARCHIVE="$(find "$EXPORT_DIR" -maxdepth 1 -name '*.tar.gz' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)"; fi
[[ -f "$ARCHIVE" ]] || { echo "MinIO backup archive not found."; exit 1; }
[[ ! -f "$ARCHIVE.sha256" ]] || (cd "$(dirname "$ARCHIVE")" && sha256sum -c "$(basename "$ARCHIVE").sha256")
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT; tar -xzf "$ARCHIVE" -C "$TMP"
grep -q '"bucket":"public-assets"' "$TMP/manifest.json" || { echo "Invalid backup manifest."; exit 1; }
cat "$TMP/manifest.json"
if [[ "$MODE" == "replace" && "$YES" != "true" ]]; then read -r -p "Replace public-assets and delete extra objects? [y/N] " answer; [[ "$answer" == "y" || "$answer" == "Y" ]] || exit 1; fi
docker compose run --rm --no-deps --entrypoint /bin/sh -v "$TMP:/backup:ro" -e RESTORE_MODE="$MODE" minio-init -c '
  set -eu
  mc alias set local http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null
  mc mb --ignore-existing local/public-assets
  if [ "$RESTORE_MODE" = replace ]; then mc mirror --overwrite --remove /backup/objects local/public-assets; else mc mirror --overwrite /backup/objects local/public-assets; fi
  mc anonymous set-json /backup/policy.json local/public-assets
  mc du local/public-assets
'
echo "MinIO restore completed ($MODE): $ARCHIVE"
