# telemetry-service 이미지 (빌드 컨텍스트: 저장소 루트 — packages/common 을 같이 넣어야 하므로)
#   docker build -f services/telemetry-service/Dockerfile -t homeiot/telemetry-service .
FROM node:22-alpine
WORKDIR /app
ENV NODE_ENV=production

# 1) 의존성만 먼저 설치 (레이어 캐시)
#    루트 package.json 의 workspaces 글롭(packages/*, services/*)은 복사된 폴더만 잡는다
COPY package.json ./
COPY packages/common/package.json packages/common/
COPY services/telemetry-service/package.json services/telemetry-service/
RUN npm install --omit=dev --no-audit --no-fund && npm cache clean --force

# 2) 소스 복사 (test/, README.md 는 .dockerignore 로 제외)
COPY packages/common packages/common
COPY services/telemetry-service services/telemetry-service

WORKDIR /app/services/telemetry-service
USER node
CMD ["node", "src/index.js"]
