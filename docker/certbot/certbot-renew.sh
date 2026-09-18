#!/bin/sh
set -eu

if [ -z "${DOMAIN:-}" ] || [ -z "${LETSENCRYPT_EMAIL:-}" ]; then
    echo "DOMAIN and LETSENCRYPT_EMAIL are required" >&2
    exit 1
fi

request_certificate() {
    certbot certonly \
        --webroot \
        --webroot-path /var/www/certbot \
        --non-interactive \
        --agree-tos \
        --email "$LETSENCRYPT_EMAIL" \
        --domain "$DOMAIN"
}

publish_certificate() {
    source_dir="/etc/letsencrypt/live/${DOMAIN}"
    mkdir -p /etc/nginx-certs
    cp -L "${source_dir}/fullchain.pem" /etc/nginx-certs/fullchain.pem.tmp
    cp -L "${source_dir}/privkey.pem" /etc/nginx-certs/privkey.pem.tmp
    chown 101:101 /etc/nginx-certs/fullchain.pem.tmp /etc/nginx-certs/privkey.pem.tmp
    chmod 0644 /etc/nginx-certs/fullchain.pem.tmp
    chmod 0600 /etc/nginx-certs/privkey.pem.tmp
    mv /etc/nginx-certs/fullchain.pem.tmp /etc/nginx-certs/fullchain.pem
    mv /etc/nginx-certs/privkey.pem.tmp /etc/nginx-certs/privkey.pem
}

until [ -s "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]; do
    request_certificate || true
    # Avoid Let's Encrypt failed-validation rate limits while DNS/NAT is fixed.
    [ -s "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ] || sleep 3600
done

publish_certificate

while :; do
    certbot renew --webroot --webroot-path /var/www/certbot --quiet || true
    publish_certificate
    sleep 43200
done
