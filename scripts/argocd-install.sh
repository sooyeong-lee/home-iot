#!/usr/bin/env bash
# =====================================================================
# [t1-base 에서 실행] 로컬 클러스터에 Argo CD 설치 + LoadBalancer(MetalLB) 로 화면 노출
#   bash scripts/argocd-install.sh
#   ARGOCD_VERSION=v3.x.y bash scripts/argocd-install.sh   # 버전 고정
# =====================================================================
set -euo pipefail
ARGOCD_VERSION="${ARGOCD_VERSION:-stable}"
URL="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
# CRD 가 커서 client-side apply 는 annotation 크기 제한에 걸림 → server-side
kubectl apply -n argocd --server-side --force-conflicts -f "$URL"
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=300s

# 화면 노출: MetalLB 대역(10.10.31.100~127)에서 IP 하나 받음
kubectl -n argocd patch svc argocd-server -p '{"spec":{"type":"LoadBalancer"}}'
for i in $(seq 1 30); do
  IP=$(kubectl -n argocd get svc argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  [ -n "$IP" ] && break; sleep 2
done
PW=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)

cat <<EOF

Argo CD 설치 완료
  화면    : https://${IP:-<kubectl -n argocd get svc argocd-server>}   (자체 서명 인증서 경고 → 계속 진행)
  계정    : admin
  비밀번호: ${PW}
  ※ 로그인 후 User Info → UPDATE PASSWORD 로 바꾸고,
    kubectl -n argocd delete secret argocd-initial-admin-secret 로 초기 비밀번호 Secret 삭제
EOF
