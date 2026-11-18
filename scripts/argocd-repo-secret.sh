#!/usr/bin/env bash
# =====================================================================
# Argo CD 가 비공개 GitHub 저장소를 읽을 수 있게 저장소 자격증명 등록
#   GITHUB_USER=sooyeong-lee GITHUB_TOKEN=<repo 읽기 PAT> bash scripts/argocd-repo-secret.sh
# 저장소가 public 이면 필요 없다.
# =====================================================================
set -euo pipefail
REPO_URL="${REPO_URL:-https://github.com/sooyeong-lee/home-iot.git}"
GITHUB_USER="${GITHUB_USER:?GITHUB_USER 필요}"
GITHUB_TOKEN="${GITHUB_TOKEN:?GITHUB_TOKEN 필요}"

kubectl -n argocd create secret generic home-iot-repo \
  --from-literal=type=git --from-literal=url="$REPO_URL" \
  --from-literal=username="$GITHUB_USER" --from-literal=password="$GITHUB_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n argocd label secret home-iot-repo argocd.argoproj.io/secret-type=repository --overwrite
echo "Argo CD 저장소 등록: ${REPO_URL}"
