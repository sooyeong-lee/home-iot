# device-service

기기 등록 · 조회 · 삭제와 현재 상태 조회를 담당합니다.

- 기기 등록/삭제 시 MQTT `meta` 토픽(retained)을 발행해서 시뮬레이터가 가상 기기를 만들고 지우게 합니다.
- MQTT 에 (재)연결될 때마다 등록된 모든 기기의 meta 를 다시 발행합니다 (브로커가 초기화돼도 시뮬레이터가 기기를 알 수 있게).
- 기기 ID 를 보내지 않으면 `<종류>-<사용자ID>-<순번 2자리>` (예: `light-5-01`) 로 자동 생성합니다.
- 상태(`device_states`)와 연결 상태(`devices.status`)는 telemetry-service 가 갱신합니다.
- control-service · telemetry-service 가 기기 소유권 확인을 위해 이 서비스를 REST 로 호출합니다.

| 항목 | 값 |
| --- | --- |
| 포트 | 3002 |
| 의존 | PostgreSQL (`devices`, `device_states`), MQTT (meta 발행) |
| 공통 엔드포인트 | `/healthz`, `/readyz`, `/metrics` (`packages/common` 의 `createService`) |

## API

모든 경로 인증 필요 (Gateway 가 넣어 준 `x-user-id`). 본인 기기만 조회 가능 — 없으면 404, 남의 기기면 403.

| 메서드 | 경로 | 설명 |
| --- | --- | --- |
| GET | `/api/v1/devices` | 내 기기 목록 + 현재 상태 (`type`, `status` 필터) (US-04) |
| POST | `/api/v1/devices` | 기기 등록 (US-03) |
| GET | `/api/v1/devices/:deviceId` | 기기 상세 (US-05) |
| GET | `/api/v1/devices/:deviceId/state` | 현재 상태 (US-05) |
| DELETE | `/api/v1/devices/:deviceId` | 기기 삭제 (US-06) |

## 환경 변수

로컬에서는 저장소 루트의 `.env` (`.env.example` 참고), 클러스터에서는 `deploy/k8s/base/configmap.yaml` 과 Secret 으로 주입합니다.

| 변수 | 기본값 | 설명 |
| --- | --- | --- |
| `PORT` | 3002 | |
| `DB_HOST` `DB_PORT` `DB_NAME` `DB_USER` `DB_PASSWORD` `DB_SCHEMA` | | PostgreSQL 접속 |
| `MQTT_URL` `MQTT_USERNAME` `MQTT_PASSWORD` | | MQTT 브로커 접속 |

## 실행 방법

먼저 저장소 루트에서 한 번만 준비합니다 (`.env`, JWT 키, `npm install`).

```bash
make setup      # 처음 한 번
make infra      # postgres + mosquitto (docker compose)
```

**이 서비스만 실행 (watch 모드)**

```bash
npm run dev -w services/device-service        # 저장소 루트에서
```

**백엔드 전체 + 개발용 게이트웨이(:8080) 한 번에**

```bash
make dev
```

**컨테이너로 실행**

```bash
docker compose --profile app up -d --build device-service
```

## 테스트

```bash
npm test -w services/device-service           # 이 서비스만
npm test                              # 저장소 전체 (루트)
```

## 이미지 빌드

빌드 컨텍스트는 **저장소 루트**입니다 (`packages/common` 을 함께 넣어야 하므로).

```bash
docker build -f services/device-service/Dockerfile -t homeiot/device-service .
```

`test/` 와 `README.md` 는 `.dockerignore` 로 이미지에서 빠집니다.

## 폴더 구조

```
services/device-service/
  src/
    index.js      라우터 · DB 처리 · MQTT meta 발행
    validate.js   기기 ID 규칙 · 등록 입력 검증 (순수 함수)
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
