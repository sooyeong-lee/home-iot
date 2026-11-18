# 클러스터용 Nginx (Envoy Gateway → nginx → Next.js)
FROM nginx:1.29-alpine
# OS 패키지 보안 업데이트 (Trivy CRITICAL 대응: brotli-libs 등)
RUN apk upgrade --no-cache \
 && rm /etc/nginx/conf.d/default.conf \
 && mkdir -p /var/cache/nginx/next
COPY web.conf /etc/nginx/conf.d/web.conf
EXPOSE 8080