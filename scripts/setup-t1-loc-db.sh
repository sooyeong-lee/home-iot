#!/usr/bin/env bash
# =====================================================================
# [t1-loc-db 에서 실행] PostgreSQL 16 설치 · 외부 접속 허용 · 계정/DB 생성
#   DB_PASSWORD=비밀번호 bash setup-t1-loc-db.sh
# 테이블(스키마 dev)은 t1-base 에서 'make db-migrate' 로 만든다.
# 이미 설치돼 있으면 설정만 맞추고 넘어간다.
# =====================================================================
set -euo pipefail
DB_NAME="${DB_NAME:-homeiot}"
DB_USER="${DB_USER:-homeiot}"
DB_PASSWORD="${DB_PASSWORD:?DB_PASSWORD 를 지정하세요}"
ALLOW_CIDR="${ALLOW_CIDR:-10.10.31.0/24}"   # t1-base + 클러스터 노드(파드는 노드 IP 로 나감)

if ! command -v psql >/dev/null || ! systemctl list-unit-files | grep -q '^postgresql'; then
  sudo apt-get update
  sudo apt-get install -y postgresql
fi
PGVER="$(ls /etc/postgresql | sort -V | tail -1)"
PGCONF="/etc/postgresql/${PGVER}/main"

# 모든 인터페이스에서 접속 허용
sudo sed -i -E "s/^#?listen_addresses\s*=.*/listen_addresses = '*'/" "${PGCONF}/postgresql.conf"
# 팀 대역에서 비밀번호 접속 허용
RULE="host    ${DB_NAME}    ${DB_USER}    ${ALLOW_CIDR}    scram-sha-256"
sudo grep -qF "$RULE" "${PGCONF}/pg_hba.conf" || echo "$RULE" | sudo tee -a "${PGCONF}/pg_hba.conf" >/dev/null
sudo systemctl restart postgresql

sudo -u postgres psql -v ON_ERROR_STOP=1 -v u="$DB_USER" -v p="$DB_PASSWORD" -v d="$DB_NAME" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'u', :'p')
 WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'u') \gexec
SELECT format('ALTER ROLE %I PASSWORD %L', :'u', :'p') \gexec
SELECT format('CREATE DATABASE %I OWNER %I', :'d', :'u')
 WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'d') \gexec
SQL

echo "PostgreSQL ${PGVER} 준비 완료: ${DB_USER}@$(hostname -I | awk '{print $1}'):5432/${DB_NAME}"
