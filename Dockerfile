FROM nginx:1.27-alpine

COPY nginx/default.conf /etc/nginx/conf.d/default.conf
COPY nginx/html/ /usr/share/nginx/html/

EXPOSE 80
