# 로컬 개발용 API Gateway (docker compose --profile app)
FROM node:22-alpine
WORKDIR /app
COPY package.json index.js ./
USER node
EXPOSE 8080
CMD ["node", "index.js"]
