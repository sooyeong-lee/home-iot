#!/usr/bin/env bash
# =====================================================================
# 클러스터가 GHCR 비공개 이미지를 받을 수 있도록 pull Secret(ghcr-pull) 생성
#   GHCR_USER=sooyeong-lee GHCR_TOKEN=<read:packages 권한 PAT> bash scripts/ghcr-pull-secret.sh
# GHCR 패키지를 public 으로 바꿨다면 필요 없다.
# =====================================================================
set -euo pipefail
GHCR_USER="${GHCR_USER:?GHCR_USER(GitHub 아이디) 필요}"
GHCR_TOKEN="${GHCR_TOKEN:?GHCR_TOKEN(read:packages 권한 PAT) 필요}"

kubectl create namespace homeiot --dry-run=client -o yaml | kubectl apply -f -
kubectl -n homeiot create secret docker-registry ghcr-pull \
  --docker-server=ghcr.io --docker-username="$GHCR_USER" --docker-password="$GHCR_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -
echo "homeiot/ghcr-pull 적용 완료"
