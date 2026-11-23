# control-service

기기 제어 명령을 발행하고 기기 응답을 기다려 결과를 돌려줍니다. 엘리베이터 호출도 처리합니다.

명령 흐름

1. device-service 에 기기 조회 (REST, `x-user-id` 전달) → 소유권 · 온라인 확인
2. `commands` 에 `requested` 저장 → MQTT `command` 발행 (`commandId` 포함)
3. 기기가 같은 `commandId` 로 `state` 를 발행하면 `completed` 로 바꾸고 결과 응답
4. `COMMAND_TIMEOUT_MS` 안에 응답이 없으면 `timeout` 저장 후 504

- `state` 는 공유 구독이 아닙니다 (명령을 보낸 인스턴스가 응답을 받아야 하므로).
- `elevator/status` 는 공유 구독(`$share/control`)으로 받아 `elevator_calls` 상태를 갱신합니다.
- 지표: `homeiot_commands_total`, `homeiot_command_roundtrip_seconds`

| 항목 | 값 |
| --- | --- |
| 포트 | 3003 |
| 의존 | PostgreSQL (`commands`, `elevator_calls`), MQTT, device-service (REST) |
| 공통 엔드포인트 | `/healthz`, `/readyz`, `/metrics` (`packages/common` 의 `createService`) |

## API

모든 경로 인증 필요 (Gateway 가 넣어 준 `x-user-id`).

| 메서드 | 경로 | 설명 |
| --- | --- | --- |
| POST | `/api/v1/devices/:deviceId/commands` | 기기 제어 (US-07 ~ US-11) |
| POST | `/api/v1/elevator/calls` | 엘리베이터 호출 → 202 (US-12) |
| GET | `/api/v1/elevator/calls/:callId` | 호출 상태 조회 (US-12) |

## 환경 변수

로컬에서는 저장소 루트의 `.env` (`.env.example` 참고), 클러스터에서는 `deploy/k8s/base/configmap.yaml` 과 Secret 으로 주입합니다.

| 변수 | 기본값 | 설명 |
| --- | --- | --- |
| `PORT` | 3003 | |
| `DB_HOST` `DB_PORT` `DB_NAME` `DB_USER` `DB_PASSWORD` `DB_SCHEMA` | | PostgreSQL 접속 |
| `MQTT_URL` `MQTT_USERNAME` `MQTT_PASSWORD` | | MQTT 브로커 접속 |
| `DEVICE_SERVICE_URL` | http://localhost:3002 | device-service 주소 |
| `COMMAND_TIMEOUT_MS` | 5000 | 기기 응답 대기 시간 |

## 실행 방법

먼저 저장소 루트에서 한 번만 준비합니다 (`.env`, JWT 키, `npm install`).

```bash
make setup      # 처음 한 번
make infra      # postgres + mosquitto (docker compose)
```

**이 서비스만 실행 (watch 모드)**

```bash
npm run dev -w services/control-service        # 저장소 루트에서
```

**백엔드 전체 + 개발용 게이트웨이(:8080) 한 번에**

```bash
make dev
```

**컨테이너로 실행**

```bash
docker compose --profile app up -d --build control-service
```

## 테스트

```bash
npm test -w services/control-service           # 이 서비스만
npm test                              # 저장소 전체 (루트)
```

## 이미지 빌드

빌드 컨텍스트는 **저장소 루트**입니다 (`packages/common` 을 함께 넣어야 하므로).

```bash
docker build -f services/control-service/Dockerfile -t homeiot/control-service .
```

`test/` 와 `README.md` 는 `.dockerignore` 로 이미지에서 빠집니다.

## 폴더 구조

```
services/control-service/
  src/
    index.js      라우터 · 명령 발행/응답 대기 · DB 처리
    validate.js   ID 생성 · 엘리베이터 호출 입력 검증 (순수 함수)
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
