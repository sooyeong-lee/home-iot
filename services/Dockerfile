# 백엔드 서비스 공용 Dockerfile (빌드 컨텍스트: 저장소 루트)
#   docker build -f services/Dockerfile --build-arg SERVICE=auth-service -t homeiot/auth-service .
FROM node:22-alpine
ARG SERVICE
RUN test -n "$SERVICE" || (echo "--build-arg SERVICE=<서비스 폴더명> 필요" && false)
WORKDIR /app
ENV NODE_ENV=production

# 1) 의존성만 먼저 설치 (레이어 캐시)
#    루트 package.json 의 workspaces 글롭(packages/*, services/*)은 복사된 폴더만 잡는다
COPY package.json ./
COPY packages/common/package.json packages/common/
COPY services/${SERVICE}/package.json services/${SERVICE}/
RUN npm install --omit=dev --no-audit --no-fund && npm cache clean --force

# 2) 소스 복사
COPY packages/common packages/common
COPY services/${SERVICE} services/${SERVICE}

WORKDIR /app/services/${SERVICE}
USER node
CMD ["node", "src/index.js"]
