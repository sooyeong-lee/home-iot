# 클러스터용 Nginx (Envoy Gateway → nginx → Next.js)
FROM nginx:1.29-alpine
RUN rm /etc/nginx/conf.d/default.conf && mkdir -p /var/cache/nginx/next
COPY web.conf /etc/nginx/conf.d/web.conf
EXPOSE 8080
