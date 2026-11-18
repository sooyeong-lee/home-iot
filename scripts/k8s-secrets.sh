#!/usr/bin/env bash
# =====================================================================
# 쿠버네티스 Secret 생성/갱신 (값은 deploy/local.env, 키는 secrets/)
#   homeiot-secrets : DB_USER, DB_PASSWORD, MQTT_USERNAME, MQTT_PASSWORD
#   homeiot-jwt     : jwt-private.pem (auth-service 토큰 발급용. 검증은 Envoy Gateway 가 공개키로)
# 코드·이미지·git 에는 비밀값을 넣지 않는다 (아키텍처 6. 비밀값 관리)
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f deploy/local.env ] || { echo "deploy/local.env 가 없습니다. cp deploy/local.env.example deploy/local.env 후 값 수정"; exit 1; }
set -a; . deploy/local.env; set +a
[ -f secrets/jwt-private.pem ] || bash scripts/gen-jwt-keys.sh

kubectl create namespace homeiot --dry-run=client -o yaml | kubectl apply -f -
kubectl -n homeiot create secret generic homeiot-secrets \
  --from-literal=DB_USER="$DB_USER" --from-literal=DB_PASSWORD="$DB_PASSWORD" \
  --from-literal=MQTT_USERNAME="$MQTT_USERNAME" --from-literal=MQTT_PASSWORD="$MQTT_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n homeiot create secret generic homeiot-jwt \
  --from-file=jwt-private.pem=secrets/jwt-private.pem \
  --dry-run=client -o yaml | kubectl apply -f -
echo "Secret 적용 완료"
