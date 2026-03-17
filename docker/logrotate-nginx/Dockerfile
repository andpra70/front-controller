FROM alpine:3.21

RUN apk add --no-cache logrotate

COPY docker/logrotate-nginx/logrotate-cron /etc/crontabs/root

CMD ["crond", "-f", "-l", "2"]
