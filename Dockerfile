FROM nginxinc/nginx-unprivileged:1.27-alpine

USER root
RUN apk add --no-cache logrotate openssl \
    && rm -f /var/log/nginx/access.log /var/log/nginx/error.log \
    && touch /var/log/nginx/front-controller-access.log /var/log/nginx/error.log \
    && mkdir -p /var/www/certbot \
    && chown -R nginx:nginx /var/log/nginx /etc/nginx/conf.d /var/www/certbot

COPY nginx/default.conf /etc/nginx/conf.d/default.conf
COPY nginx/html/ /usr/share/nginx/html/
COPY docker/front-controller/entrypoint.sh /usr/local/bin/front-controller-entrypoint.sh
COPY docker/front-controller/logrotate.conf /etc/logrotate.d/front-controller

RUN chmod 0755 /usr/local/bin/front-controller-entrypoint.sh

USER nginx

EXPOSE 8080
EXPOSE 8443

ENTRYPOINT ["/usr/local/bin/front-controller-entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
