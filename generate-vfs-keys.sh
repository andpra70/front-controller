#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTH_KEYS="$SCRIPT_DIR/../app/oauth2/keys"; VFS_KEYS="$SCRIPT_DIR/../app/vfs2/keys"
mkdir -p "$AUTH_KEYS" "$VFS_KEYS"
[[ ! -e "$AUTH_KEYS/private.pem" ]] || { echo "Private key already exists; refusing to overwrite."; exit 1; }
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out "$AUTH_KEYS/private.pem"
openssl rsa -pubout -in "$AUTH_KEYS/private.pem" -out "$VFS_KEYS/public.pem"
chmod 600 "$AUTH_KEYS/private.pem"; chmod 644 "$VFS_KEYS/public.pem"
echo "RS256 key pair generated. Keep app/oauth2/keys/private.pem secret."
