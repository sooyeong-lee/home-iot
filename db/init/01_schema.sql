-- =====================================================================
-- Home IoT DB 스키마 (DB 명세서 v0.1 기준, 테이블 8개)
--  - PostgreSQL 하나, 개발 스키마 dev 하나에 모든 테이블을 둔다
--  - 시각은 TIMESTAMPTZ(UTC)
--  - 명세서 대비 추가: devices.location (와이어프레임 '설치 위치' 입력값)
-- 여러 번 실행해도 안전하도록 IF NOT EXISTS 사용
-- =====================================================================
CREATE SCHEMA IF NOT EXISTS dev;
SET search_path TO dev;

-- 1. users (auth-service)
CREATE TABLE IF NOT EXISTS users (
  user_id       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  email         VARCHAR(255) NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  name          VARCHAR(50)  NOT NULL,
  created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
  CONSTRAINT uq_users_email UNIQUE (email)
);

-- 2. refresh_tokens (auth-service)
CREATE TABLE IF NOT EXISTS refresh_tokens (
  token_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id    BIGINT       NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  token_hash VARCHAR(255) NOT NULL,
  expires_at TIMESTAMPTZ  NOT NULL,
  revoked_at TIMESTAMPTZ,
  CONSTRAINT uq_refresh_tokens_hash UNIQUE (token_hash)
);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user ON refresh_tokens (user_id);

-- 3. devices (device-service)
CREATE TABLE IF NOT EXISTS devices (
  device_id    VARCHAR(50)  PRIMARY KEY,
  user_id      BIGINT       NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  name         VARCHAR(100) NOT NULL,
  type         VARCHAR(20)  NOT NULL
               CHECK (type IN ('light','aircon','heater','purifier','curtain','elevator')),
  location     VARCHAR(50),
  status       VARCHAR(10)  NOT NULL DEFAULT 'offline' CHECK (status IN ('online','offline')),
  last_seen_at TIMESTAMPTZ,
  created_at   TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_devices_user_type ON devices (user_id, type);

-- 4. device_states (device-service 조회 / telemetry-service 갱신)
CREATE TABLE IF NOT EXISTS device_states (
  device_id  VARCHAR(50) PRIMARY KEY REFERENCES devices(device_id) ON DELETE CASCADE,
  power      VARCHAR(3)  CHECK (power IN ('on','off')),
  state      JSONB       NOT NULL DEFAULT '{}',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 5. device_events (telemetry-service = 명세서의 monitoring-service)
CREATE TABLE IF NOT EXISTS device_events (
  event_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  device_id   VARCHAR(50) NOT NULL REFERENCES devices(device_id) ON DELETE CASCADE,
  event_type  VARCHAR(30) NOT NULL
              CHECK (event_type IN ('STATE_CHANGED','COMMAND_SENT','ONLINE','OFFLINE')),
  payload     JSONB       NOT NULL DEFAULT '{}',
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_device_events_device_time ON device_events (device_id, occurred_at DESC);

-- 6. commands (control-service)
CREATE TABLE IF NOT EXISTS commands (
  command_id   VARCHAR(50) PRIMARY KEY,
  device_id    VARCHAR(50) NOT NULL REFERENCES devices(device_id) ON DELETE CASCADE,
  user_id      BIGINT      NOT NULL REFERENCES users(user_id) ON DELETE RESTRICT,
  command      VARCHAR(30) NOT NULL,
  params       JSONB       NOT NULL DEFAULT '{}',
  status       VARCHAR(15) NOT NULL DEFAULT 'requested'
               CHECK (status IN ('requested','completed','failed','timeout')),
  requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_commands_device_time ON commands (device_id, requested_at DESC);
CREATE INDEX IF NOT EXISTS idx_commands_user ON commands (user_id);

-- 7. elevator_calls (control-service)
CREATE TABLE IF NOT EXISTS elevator_calls (
  call_id      VARCHAR(50) PRIMARY KEY,
  device_id    VARCHAR(50) NOT NULL REFERENCES devices(device_id) ON DELETE CASCADE,
  user_id      BIGINT      NOT NULL REFERENCES users(user_id) ON DELETE RESTRICT,
  floor        INTEGER     NOT NULL,
  direction    VARCHAR(4)  CHECK (direction IN ('up','down')),
  status       VARCHAR(15) NOT NULL DEFAULT 'requested'
               CHECK (status IN ('requested','arriving','arrived','failed')),
  requested_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_elevator_calls_device_status ON elevator_calls (device_id, status);

-- 8. simulators (simulator-service, US-15 용으로 예약 — 현재 시뮬레이터는 DB에 접근하지 않음)
CREATE TABLE IF NOT EXISTS simulators (
  simulator_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  device_id    VARCHAR(50) NOT NULL REFERENCES devices(device_id) ON DELETE CASCADE,
  type         VARCHAR(20) NOT NULL,
  status       VARCHAR(10) NOT NULL DEFAULT 'stopped' CHECK (status IN ('running','stopped')),
  interval_sec INTEGER     NOT NULL DEFAULT 5,
  CONSTRAINT uq_simulators_device UNIQUE (device_id)
);
