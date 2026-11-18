# Home IoT 개발 명령 모음 (t1-base)
#   make help
SHELL := /bin/bash
-include deploy/local.env
DB_IP ?= 10.10.31.10

.PHONY: urls help setup keys install infra infra-down dev web-dev up down logs db-shell db-migrate db-reset test smoke argocd-install gitops-secrets argocd-app argocd-status jenkins-up jenkins-down jenkins-logs \
        k8s-status k8s-logs k8s-delete

.DEFAULT_GOAL := help

urls: ## 브라우저 접속 주소 출력 (.env 의 DEV_HOSTS 기준)
	@H=$$(grep -E '^DEV_HOSTS=' .env 2>/dev/null | cut -d= -f2 | cut -d, -f1); H=$${H:-$$(hostname -I | awk '{print $$1}')}; \
	echo "방법 A  화면      http://$$H:3000"; echo "        시뮬레이터 http://$$H:3005/simulator/"; \
	echo "방법 B  화면      http://$$H:8080"; echo "        시뮬레이터 http://$$H:8080/simulator/"

help: ## 명령 목록
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n",$$1,$$2}'

# ---------- 로컬 개발 ----------
setup: ## .env, deploy/local.env, JWT 키 준비 + npm install
	@[ -f .env ] || cp .env.example .env
	@[ -f deploy/local.env ] || cp deploy/local.env.example deploy/local.env
	bash scripts/gen-jwt-keys.sh
	npm install
	cd web && npm install

keys: ## JWT 키 다시 생성 (FORCE=1)
	FORCE=1 bash scripts/gen-jwt-keys.sh

infra: ## postgres + mosquitto 만 실행 (docker compose)
	docker compose up -d

infra-down: ## 인프라 중지
	docker compose down

dev: ## 백엔드 5개 watch 모드 실행 (호스트)
	npm run dev:services

web-dev: ## Next.js 개발 서버 (http://<t1-base>:3000)
	cd web && npm run dev

up: ## 전체를 컨테이너로 실행 (http://<t1-base>:8080)
	docker compose --profile app up -d --build

down: ## 전체 중지
	docker compose --profile app down

logs: ## 컨테이너 로그
	docker compose --profile app logs -f --tail=100

db-shell: ## 로컬 postgres 접속
	docker compose exec -e PGOPTIONS='-c search_path=dev' postgres psql -U homeiot -d homeiot

db-reset: ## 로컬 postgres 데이터 초기화 (볼륨 삭제 후 재생성)
	docker compose down -v && docker compose up -d

test: ## 단위 테스트
	npm test

smoke: ## 흐름 확인 (BASE_URL=http://... 로 대상 변경)
	bash scripts/smoke-test.sh

# ---------- 로컬 클러스터 (DB 준비 · 상태 확인) ----------
db-migrate: ## t1-loc-db 에 테이블 생성 (dev 스키마)
	PGPASSWORD="$(DB_PASSWORD)" psql -h $(DB_IP) -U $(DB_USER) -d $(DB_NAME) -v ON_ERROR_STOP=1 -f db/init/01_schema.sql

k8s-status: ## 배포 상태
	kubectl -n homeiot get pods,svc,gateway,httproute -o wide

k8s-logs: ## 서비스 로그 (S=auth-service)
	kubectl -n homeiot logs -f deploy/$(or $(S),control-service) --tail=100

k8s-delete: ## Argo CD Application 삭제 → 배포한 리소스도 함께 삭제 (Secret 은 남음)
	kubectl delete -f deploy/argocd/application.yaml

# ---------- GitOps (GitHub Actions → GHCR → Argo CD) ----------
argocd-install: ## Argo CD 설치 + LoadBalancer 노출
	bash scripts/argocd-install.sh

gitops-secrets: ## Argo CD 배포 전 Secret 준비 (DB·MQTT·JWT + GHCR pull, GHCR_USER/GHCR_TOKEN 필요)
	bash scripts/k8s-secrets.sh
	bash scripts/ghcr-pull-secret.sh
	kubectl apply -f secrets/security-policy.yaml

argocd-app: ## Argo CD Application 등록 (main 자동 배포 시작)
	kubectl apply -f deploy/argocd/application.yaml

argocd-status: ## Argo CD 동기화 상태
	kubectl -n argocd get application home-iot -o jsonpath='{.status.sync.status}{" / "}{.status.health.status}{" / "}{.status.sync.revision}{"\n"}'

# ---------- Jenkins (GitHub Actions 대신 쓸 때, 가이드 10절) ----------
jenkins-up: ## Jenkins 빌드·실행 (http://<t1-base>:8090)
	bash scripts/jenkins-up.sh

jenkins-down: ## Jenkins 중지 (데이터 유지)
	bash scripts/jenkins-up.sh down

jenkins-logs: ## Jenkins 로그
	docker logs -f --tail=100 homeiot-jenkins
