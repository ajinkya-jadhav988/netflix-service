FROM nginxinc/nginx-unprivileged:stable-alpine

# Non-root (uid 101) nginx listening on 8080; custom site config + static files only
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html app.js style.css /usr/share/nginx/html/
COPY images /usr/share/nginx/html/images

USER 101
EXPOSE 8080

