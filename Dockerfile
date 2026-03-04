FROM nginx:1.27-alpine

COPY nginx/default.conf /etc/nginx/conf.d/default.conf
COPY nginx/html/ /usr/share/nginx/html/
COPY certs/live/ /etc/nginx/certs/

EXPOSE 55000
EXPOSE 55443
