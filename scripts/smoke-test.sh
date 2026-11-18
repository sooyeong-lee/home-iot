#!/usr/bin/env bash
# =====================================================================
# 전체 흐름 확인 (회원가입 → 로그인 → 기기 등록(ID 자동 생성 포함) → 온라인 → 조명 켜기 → 이력 → 엘리베이터 호출)
#   bash scripts/smoke-test.sh                          # compose 게이트웨이 (http://localhost:8080)
#   BASE_URL=http://10.10.31.101 bash scripts/smoke-test.sh   # 클러스터 Gateway 주소
# 시뮬레이터가 떠 있어야 한다.
# =====================================================================
set -euo pipefail
BASE_URL="${BASE_URL:-http://localhost:8080}"
API="${BASE_URL}/api/v1"
SUF="$(date +%s)"
EMAIL="smoke-${SUF}@example.com"
LIGHT="light-smoke-${SUF}"
ELEV="elevator-smoke-${SUF}"
pass() { printf '\033[32m✔ %s\033[0m\n' "$*"; }
fail() { printf '\033[31m✘ %s\033[0m\n' "$*"; exit 1; }
req() { # method path [json]
  curl -sS -X "$1" "${API}$2" -H 'Content-Type: application/json' ${TOKEN:+-H "Authorization: Bearer ${TOKEN}"} ${3:+-d "$3"}
}

echo "대상: ${BASE_URL}"
r=$(req POST /auth/signup "{\"email\":\"${EMAIL}\",\"password\":\"password123\",\"name\":\"스모크\"}")
[ "$(echo "$r" | jq -r .success)" = true ] && pass "회원가입" || fail "회원가입: $r"
r=$(req POST /auth/signup "{\"email\":\"${EMAIL}\",\"password\":\"password123\",\"name\":\"스모크\"}")
[ "$(echo "$r" | jq -r .error.code)" = EMAIL_DUPLICATED ] && pass "중복 가입 409" || fail "중복 가입: $r"

r=$(req POST /auth/login "{\"email\":\"${EMAIL}\",\"password\":\"password123\"}")
TOKEN=$(echo "$r" | jq -r .data.accessToken); [ "$TOKEN" != null ] && pass "로그인" || fail "로그인: $r"

code=$(curl -s -o /dev/null -w '%{http_code}' "${API}/devices")
[ "$code" = 401 ] && pass "토큰 없이 조회 401" || fail "토큰 없이 조회: ${code}"
code=$(curl -s -o /dev/null -w '%{http_code}' -H 'x-user-id: 1' "${API}/devices")
[ "$code" = 401 ] && pass "x-user-id 위조 헤더만으로는 401 (Gateway 검증)" || fail "위조 헤더: ${code}"
code=$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $(echo "$r" | jq -r .data.refreshToken)" "${API}/devices")
[ "$code" = 401 ] && pass "Refresh 토큰으로 API 호출 401" || fail "Refresh 토큰 거부: ${code}"

r=$(req POST /devices "{\"deviceId\":\"${LIGHT}\",\"name\":\"거실 조명\",\"type\":\"light\",\"location\":\"거실\"}")
[ "$(echo "$r" | jq -r .success)" = true ] && pass "조명 등록" || fail "조명 등록: $r"
r=$(req POST /devices "{\"deviceId\":\"${ELEV}\",\"name\":\"엘리베이터\",\"type\":\"elevator\"}")
[ "$(echo "$r" | jq -r .success)" = true ] && pass "엘리베이터 등록" || fail "엘리베이터 등록: $r"
r=$(req POST /devices '{"name":"안방 공기청정기","type":"purifier","location":"안방"}')
AUTO=$(echo "$r" | jq -r .data.deviceId)
[[ "$AUTO" =~ ^purifier-[0-9]+-[0-9]{2}$ ]] && pass "기기 ID 자동 생성 (${AUTO})" || fail "자동 ID: $r"

for i in $(seq 1 30); do
  st=$(req GET "/devices/${LIGHT}" | jq -r .data.status)
  [ "$st" = online ] && break; sleep 1
done
[ "$st" = online ] && pass "시뮬레이터 연결 → online" || fail "기기가 online 이 되지 않음 (시뮬레이터 확인)"

r=$(req POST "/devices/${LIGHT}/commands" '{"command":"SET_POWER","params":{"power":"on"}}')
[ "$(echo "$r" | jq -r .data.state.power)" = on ] && pass "조명 켜기 (명령 → MQTT → 응답)" || fail "조명 켜기: $r"
r=$(req POST "/devices/${LIGHT}/commands" '{"command":"SET_BRIGHTNESS","params":{"brightness":150}}')
[ "$(echo "$r" | jq -r .error.code)" = INVALID_REQUEST ] && pass "밝기 범위 오류 400" || fail "범위 검증: $r"
r=$(req POST "/devices/${LIGHT}/commands" '{"command":"SET_TEMPERATURE","params":{"temperature":20}}')
[ "$(echo "$r" | jq -r .error.code)" = UNSUPPORTED_COMMAND ] && pass "미지원 명령 422" || fail "미지원 명령: $r"

sleep 1
r=$(req GET "/devices/${LIGHT}/state")
[ "$(echo "$r" | jq -r .data.power)" = on ] && pass "상태 저장 (telemetry → DB)" || fail "상태 조회: $r"
r=$(req GET "/devices/${LIGHT}/events?limit=20")
echo "$r" | jq -e '.data | map(.type) | index("COMMAND_SENT") != null and index("STATE_CHANGED") != null' >/dev/null \
  && pass "이벤트 이력 (COMMAND_SENT, STATE_CHANGED)" || fail "이벤트: $r"

for i in $(seq 1 30); do
  st=$(req GET "/devices/${ELEV}" | jq -r .data.status); [ "$st" = online ] && break; sleep 1
done
r=$(req POST /elevator/calls "{\"deviceId\":\"${ELEV}\",\"floor\":3}")
CALL=$(echo "$r" | jq -r .data.callId); [ "$CALL" != null ] && pass "엘리베이터 호출 202" || fail "호출: $r"
r=$(req POST /elevator/calls "{\"deviceId\":\"${ELEV}\",\"floor\":5}")
[ "$(echo "$r" | jq -r .error.code)" = ELEVATOR_ALREADY_CALLED ] && pass "중복 호출 409" || fail "중복 호출: $r"
for i in $(seq 1 20); do
  st=$(req GET "/elevator/calls/${CALL}" | jq -r .data.status); [ "$st" = arrived ] && break; sleep 1
done
[ "$st" = arrived ] && pass "엘리베이터 도착 (requested → arriving → arrived)" || fail "도착 안 함: ${st}"

req DELETE "/devices/${LIGHT}" >/dev/null; req DELETE "/devices/${ELEV}" >/dev/null; req DELETE "/devices/${AUTO}" >/dev/null
pass "정리 완료 — 모든 확인 통과"
