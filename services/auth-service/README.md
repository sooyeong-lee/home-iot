# auth-service

회원가입 · 로그인 · 토큰 재발급 · 로그아웃을 처리하고 JWT(RS256)를 발급합니다.

- 토큰 **발급만** 합니다. API 요청의 Access 토큰 검증은 Gateway(클러스터: Envoy, 로컬: `tools/dev-gateway`)가 하고,
  이 서비스도 다른 서비스처럼 Gateway 가 넣어 준 `x-user-id` 헤더로 사용자를 식별합니다.
- Access 토큰 `aud=homeiot`, Refresh 토큰 `aud=homeiot-refresh` (Gateway 가 거부 → `/auth/refresh` 에서만 이 서비스가 확인)
- Refresh 토큰은 해시(sha256)로 `refresh_tokens` 테이블에 저장하고, 재발급할 때마다 회전합니다.

| 항목 | 값 |
| --- | --- |
| 포트 | 3001 |
| 의존 | PostgreSQL (`users`, `refresh_tokens`) |
| 공통 엔드포인트 | `/healthz`, `/readyz`, `/metrics` (`packages/common` 의 `createService`) |

## API

| 메서드 | 경로 | 인증 | 설명 |
| --- | --- | --- | --- |
| POST | `/api/v1/auth/signup` | - | 회원가입 (US-01) |
| POST | `/api/v1/auth/login` | - | 로그인 → Access/Refresh 토큰 (US-02) |
| POST | `/api/v1/auth/refresh` | - | Access 토큰 재발급 (Refresh 토큰 회전) |
| POST | `/api/v1/auth/logout` | 필요 | 로그아웃 (Refresh 토큰 폐기) |
| GET | `/api/v1/users/me` | 필요 | 내 정보 |
| GET | `/api/v1/auth/.well-known/jwks.json` | - | 공개키 (JWKS) |

## 환경 변수

로컬에서는 저장소 루트의 `.env` (`.env.example` 참고), 클러스터에서는 `deploy/k8s/base/configmap.yaml` 과 Secret 으로 주입합니다.

| 변수 | 기본값 | 설명 |
| --- | --- | --- |
| `PORT` | 3001 | |
| `DB_HOST` `DB_PORT` `DB_NAME` `DB_USER` `DB_PASSWORD` `DB_SCHEMA` | | PostgreSQL 접속 |
| `JWT_PRIVATE_KEY_FILE` (또는 `JWT_PRIVATE_KEY`) | | 토큰 서명용 개인키. **이 서비스만** 가짐 (`scripts/gen-jwt-keys.sh`) |
| `JWT_ISSUER` | homeiot-auth | |
| `JWT_AUDIENCE` | homeiot | |
| `JWT_KID` | homeiot-1 | |
| `ACCESS_TOKEN_TTL_SEC` | 3600 | |
| `REFRESH_TOKEN_TTL_SEC` | 1209600 (14일) | |

## 실행 방법

먼저 저장소 루트에서 한 번만 준비합니다 (`.env`, JWT 키, `npm install`).

```bash
make setup      # 처음 한 번
make infra      # postgres + mosquitto (docker compose)
```

**이 서비스만 실행 (watch 모드)**

```bash
npm run dev -w services/auth-service        # 저장소 루트에서
```

**백엔드 전체 + 개발용 게이트웨이(:8080) 한 번에**

```bash
make dev
```

**컨테이너로 실행**

```bash
docker compose --profile app up -d --build auth-service
```

## 테스트

```bash
npm test -w services/auth-service           # 이 서비스만
npm test                              # 저장소 전체 (루트)
```

## 이미지 빌드

빌드 컨텍스트는 **저장소 루트**입니다 (`packages/common` 을 함께 넣어야 하므로).

```bash
docker build -f services/auth-service/Dockerfile -t homeiot/auth-service .
```

`test/` 와 `README.md` 는 `.dockerignore` 로 이미지에서 빠집니다.

## 폴더 구조

```
services/auth-service/
  src/
    index.js      라우터 · 토큰 발급 · DB 처리
    validate.js   회원가입 입력 검증 (순수 함수)
  test/
    validate.test.js
  Dockerfile
  README.md
```

## 담당

| 역할 | 이름 | 연락처 |
| --- | --- | --- |
| 담당자 | (작성 필요) | |
| 부담당 | (작성 필요) | |
