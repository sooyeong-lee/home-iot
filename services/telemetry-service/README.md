# telemetry-service

기기가 보내는 상태를 구독해서 저장하고, 이력 조회 API 를 제공합니다. (DB 명세서의 monitoring-service)

MQTT 구독 — 공유 구독 `$share/telemetry` (레플리카가 늘어도 메시지를 한 번만 처리)

| 토픽 | 처리 |
| --- | --- |
| `.../state` | `device_states` 갱신, `devices.status=online` · `last_seen_at` 갱신. 값이 바뀌면 `STATE_CHANGED`, 오프라인이었으면 `ONLINE` 이벤트 |
| `.../status` | 기기가 직접 보고한 online / offline 반영 |
| `.../command` | `COMMAND_SENT` 이벤트 |

- 5초마다 `OFFLINE_AFTER_SEC` 동안 보고가 없는 기기를 offline 으로 바꾸고 `OFFLINE` 이벤트를 남깁니다.
- 지표: `homeiot_mqtt_messages_total`, `homeiot_devices_online`

| 항목 | 값 |
| --- | --- |
| 포트 | 3004 |
| 의존 | PostgreSQL (`devices`, `device_states`, `device_events`), MQTT, device-service (REST) |
| 공통 엔드포인트 | `/healthz`, `/readyz`, `/metrics` (`packages/common` 의 `createService`) |

## API

인증 필요 (Gateway 가 넣어 준 `x-user-id`). 소유권 확인은 device-service 에 맡깁니다 (404/403 그대로 전달).

| 메서드 | 경로 | 설명 |
| --- | --- | --- |
| GET | `/api/v1/devices/:deviceId/events` | 이력 조회 (US-14). `from`, `to` (ISO 8601), `type` (`STATE_CHANGED`·`COMMAND_SENT`·`ONLINE`·`OFFLINE`), `limit` (기본 50, 최대 500) |

## 환경 변수

로컬에서는 저장소 루트의 `.env` (`.env.example` 참고), 클러스터에서는 `deploy/k8s/base/configmap.yaml` 과 Secret 으로 주입합니다.

| 변수 | 기본값 | 설명 |
| --- | --- | --- |
| `PORT` | 3004 | |
| `DB_HOST` `DB_PORT` `DB_NAME` `DB_USER` `DB_PASSWORD` `DB_SCHEMA` | | PostgreSQL 접속 |
| `MQTT_URL` `MQTT_USERNAME` `MQTT_PASSWORD` | | MQTT 브로커 접속 |
| `DEVICE_SERVICE_URL` | http://localhost:3002 | device-service 주소 |
| `OFFLINE_AFTER_SEC` | 20 | 이 시간 동안 보고가 없으면 offline |

## 실행 방법

먼저 저장소 루트에서 한 번만 준비합니다 (`.env`, JWT 키, `npm install`).

```bash
make setup      # 처음 한 번
make infra      # postgres + mosquitto (docker compose)
```

**이 서비스만 실행 (watch 모드)**

```bash
npm run dev -w services/telemetry-service        # 저장소 루트에서
```

**백엔드 전체 + 개발용 게이트웨이(:8080) 한 번에**

```bash
make dev
```

**컨테이너로 실행**

```bash
docker compose --profile app up -d --build telemetry-service
```

## 테스트

```bash
npm test -w services/telemetry-service           # 이 서비스만
npm test                              # 저장소 전체 (루트)
```

## 이미지 빌드

빌드 컨텍스트는 **저장소 루트**입니다 (`packages/common` 을 함께 넣어야 하므로).

```bash
docker build -f services/telemetry-service/Dockerfile -t homeiot/telemetry-service .
```

`test/` 와 `README.md` 는 `.dockerignore` 로 이미지에서 빠집니다.

## 폴더 구조

```
services/telemetry-service/
  src/
    index.js      MQTT 구독 처리 · 오프라인 판정 · 라우터
    query.js      이력 조회 쿼리 파라미터 해석 (순수 함수)
  test/
    query.test.js
  Dockerfile
  README.md
```

## 담당

| 역할 | 이름 | 연락처 |
| --- | --- | --- |
| 담당자 | (작성 필요) | |
| 부담당 | (작성 필요) | |
