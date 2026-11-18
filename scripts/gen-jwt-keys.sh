#!/usr/bin/env bash
# =====================================================================
# JWT 서명키(RS256) 생성
#   secrets/jwt-private.pem   auth-service 만 사용 (토큰 발급 서명)
#   secrets/jwt-public.pem    Gateway 만 사용 (토큰 검증: 로컬 dev-gateway / 클러스터 Envoy 는 jwks 로)
#   secrets/jwks.json         공개키 JWKS
#   secrets/security-policy.yaml   Envoy Gateway JWT 검증 정책 (공개키만 포함, make gitops-secrets 가 적용)
# 이미 있으면 그대로 둔다 (다시 만들려면 FORCE=1)
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
KID="${JWT_KID:-homeiot-1}"
mkdir -p secrets

if [ ! -f secrets/jwt-private.pem ] || [ "${FORCE:-0}" = "1" ]; then
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out secrets/jwt-private.pem 2>/dev/null
  openssl pkey -in secrets/jwt-private.pem -pubout -out secrets/jwt-public.pem
  chmod 600 secrets/jwt-private.pem
  echo "키 생성: secrets/jwt-private.pem, secrets/jwt-public.pem"
else
  echo "기존 키 사용 (새로 만들려면 FORCE=1)"
fi

node -e '
const crypto = require("crypto"); const fs = require("fs");
const jwk = crypto.createPublicKey(fs.readFileSync("secrets/jwt-public.pem")).export({ format: "jwk" });
fs.writeFileSync("secrets/jwks.json", JSON.stringify({ keys: [{ ...jwk, kid: process.argv[1], alg: "RS256", use: "sig" }] }));
' "$KID"

JWKS="$(cat secrets/jwks.json)"
cat > secrets/security-policy.yaml <<EOF
# 자동 생성 파일 (scripts/gen-jwt-keys.sh) — 공개키만 들어 있음
# HTTPRoute 'api' 로 들어오는 모든 요청의 Access 토큰을 Envoy Gateway 에서 검증한다 (검증은 여기서만).
# 검증에 성공하면 claim 을 헤더로 넣어 서비스에 전달: sub → x-user-id, email → x-user-email
# Refresh 토큰은 aud 가 homeiot-refresh 라서 여기서 거부된다.
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: api-jwt
  namespace: homeiot
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: api
  jwt:
    providers:
      - name: homeiot-auth
        issuer: homeiot-auth
        audiences: [homeiot]
        localJWKS:
          type: Inline
          inline: '${JWKS}'
        claimToHeaders:
          - header: x-user-id
            claim: sub
          - header: x-user-email
            claim: email
EOF
echo "생성: secrets/jwks.json, secrets/security-policy.yaml"
