#!/bin/sh
set -eu

case "${DOMAIN:-}" in
    ""|*[!A-Za-z0-9.-]*)
        echo "DOMAIN is missing or contains invalid characters" >&2
        exit 1
        ;;
esac

TLS_DIR=/tmp/front-controller-tls
CERT_SOURCE=/etc/nginx-certs/fullchain.pem
KEY_SOURCE=/etc/nginx-certs/privkey.pem
CERT_TARGET="${TLS_DIR}/fullchain.pem"
KEY_TARGET="${TLS_DIR}/privkey.pem"

mkdir -p "$TLS_DIR" /var/www/certbot

install_certificate() {
    cert_tmp="${CERT_TARGET}.tmp"
    key_tmp="${KEY_TARGET}.tmp"
    cp -L "$CERT_SOURCE" "$cert_tmp"
    cp -L "$KEY_SOURCE" "$key_tmp"
    chmod 0644 "$cert_tmp"
    chmod 0600 "$key_tmp"
    mv "$cert_tmp" "$CERT_TARGET"
    mv "$key_tmp" "$KEY_TARGET"
}

if [ -s "$CERT_SOURCE" ] && [ -s "$KEY_SOURCE" ]; then
    install_certificate
else
    openssl req -x509 -nodes -newkey rsa:2048 \
        -keyout "$KEY_TARGET" \
        -out "$CERT_TARGET" \
        -days 1 \
        -subj "/CN=${DOMAIN}" \
        -addext "subjectAltName=DNS:${DOMAIN}" >/dev/null 2>&1
fi

certificate_watch() {
    while :; do
        sleep 60
        if [ -s "$CERT_SOURCE" ] && [ -s "$KEY_SOURCE" ] && \
           ! cmp -s "$CERT_SOURCE" "$CERT_TARGET"; then
            install_certificate
            nginx -t && nginx -s reload
        fi
    done
}

logrotate_loop() {
    while :; do
        /usr/sbin/logrotate -s /tmp/logrotate.status /etc/logrotate.d/front-controller
        sleep 86400
    done
}

certificate_watch &
certificate_watch_pid=$!
logrotate_loop &
logrotate_pid=$!

"$@" &
main_pid=$!

terminate() {
    kill -TERM "$main_pid" 2>/dev/null || true
}

trap terminate INT TERM QUIT

status=0
wait "$main_pid" || status=$?
kill "$certificate_watch_pid" "$logrotate_pid" 2>/dev/null || true
wait "$certificate_watch_pid" "$logrotate_pid" 2>/dev/null || true

exit "$status"
