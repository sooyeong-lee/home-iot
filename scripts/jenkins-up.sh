#!/usr/bin/env bash
# =====================================================================
# [t1-base 에서 실행] Jenkins 빌드·실행 (ci/jenkins)
#   bash scripts/jenkins-up.sh          # 처음 실행 / 설정 변경 후 다시 실행
#   bash scripts/jenkins-up.sh down     # 중지 (데이터 볼륨은 유지)
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")/../ci/jenkins"

if [ "${1:-up}" = "down" ]; then docker compose down; exit 0; fi

[ -f .env ] || { cp .env.example .env; echo "ci/jenkins/.env 를 만들었습니다. 비밀번호와 GITHUB_TOKEN 을 넣고 다시 실행하세요."; exit 1; }
grep -q 'change-me' .env && { echo "ci/jenkins/.env 에 change-me 값이 남아 있습니다. 수정 후 다시 실행하세요."; exit 1; }

export DOCKER_GID="$(getent group docker | cut -d: -f3)"
docker compose up -d --build

URL="$(grep -E '^JENKINS_URL=' .env | cut -d= -f2-)"
echo "Jenkins 시작 중… (처음은 플러그인 로딩으로 1~2분)"
for i in $(seq 1 60); do
  code=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8090/login || true)
  [ "$code" = 200 ] && break; sleep 3
done
docker exec homeiot-jenkins docker version --format 'docker 연결 확인: 서버 {{.Server.Version}}' \
  || echo "!! 컨테이너에서 docker.sock 접근 실패 — DOCKER_GID 확인"
echo "Jenkins: ${URL}  (계정: ci/jenkins/.env 의 JENKINS_ADMIN_ID)"
