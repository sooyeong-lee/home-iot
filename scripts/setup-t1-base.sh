#!/usr/bin/env bash
# =====================================================================
# t1-base 개발 VM 초기 설정 (Ubuntu 24.04, lab 계정으로 실행)
#   bash scripts/setup-t1-base.sh
# 설치: Docker(+compose/buildx), Node.js 22,
#       kubectl v1.37, git, gh, psql, mosquitto-clients, jq, make, openssl
# 여러 번 실행해도 안전하게 작성 (이미 있으면 건너뜀)
# =====================================================================
set -euo pipefail

CP_IP="${CP_IP:-10.10.31.11}"
K8S_MINOR="${K8S_MINOR:-v1.37}"

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

step "기본 패키지"
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg git jq make unzip openssl \
  postgresql-client mosquitto-clients apt-transport-https

step "Docker (공식 저장소)"
if ! command -v docker >/dev/null; then
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
sudo usermod -aG docker "$USER"

step "Node.js 22"
if ! command -v node >/dev/null || [ "$(node -p 'process.versions.node.split(".")[0]')" -lt 22 ]; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
  sudo apt-get install -y nodejs
fi

step "kubectl ${K8S_MINOR}"
if ! command -v kubectl >/dev/null; then
  sudo mkdir -p -m 755 /etc/apt/keyrings
  curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/Release.key" | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/ /" \
    | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
  sudo apt-get update
  sudo apt-get install -y kubectl
fi

step "GitHub CLI"
command -v gh >/dev/null || sudo apt-get install -y gh

step "kubeconfig (t1-loc-cp ${CP_IP} 에서 복사)"
mkdir -p ~/.kube
if [ ! -f ~/.kube/config ]; then
  echo "t1-loc-cp 의 lab 계정 비밀번호를 물어볼 수 있습니다."
  scp "lab@${CP_IP}:~/.kube/config" ~/.kube/config && chmod 600 ~/.kube/config \
    || echo "!! kubeconfig 복사 실패 — 클러스터 준비 후 다시 실행하세요: scp lab@${CP_IP}:~/.kube/config ~/.kube/config"
fi

step "확인"
docker --version; docker compose version; node -v; npm -v; kubectl version --client | head -1
kubectl get nodes 2>/dev/null || echo "(kubectl get nodes 실패: kubeconfig 확인)"

cat <<EOF

완료. docker 그룹 적용을 위해 한 번 로그아웃 후 다시 접속하거나 'newgrp docker' 를 실행하세요.
EOF
