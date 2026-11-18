# Home IoT 로컬 개발 환경 · 배포 가이드

t1-base에서 개발하고, 로컬 클러스터(t1-loc-cp · t1-loc-w1 · t1-loc-w2)에 배포해서 테스트하는 절차입니다.
클러스터 배포는 GitOps로만 합니다. main 브랜치에 merge하면 GitHub Actions가 이미지를 빌드해 GHCR에 올리고, Argo CD가 매니페스트 변경을 보고 자동으로 배포합니다 (7절). GitHub Actions 대신 Jenkins로 빌드하는 방법은 10절에 있습니다.

> 기준 문서: Home IoT 아키텍처 · API 명세서 v0.1 · DB 명세서 v0.1 · 와이어프레임 v0.1 · 기술 스택(Nginx 추가) · kubeadm 클러스터 구축 가이드(2026-11-04)

---

## 0. 한눈에 보기

```
[브라우저]
   │ http://<Gateway IP>/  (클러스터: Envoy Gateway)   또는  http://<t1-base>:8080 (로컬: dev-gateway)
   ▼
Envoy Gateway ──/api/v1/auth, /users──────────▶ auth-service      :3001 ─┐
 (JWT 검증은  ──/api/v1/devices/{id}/commands─▶ control-service   :3003 ─┤
  여기서만)   ──/api/v1/elevator/*────────────▶ control-service          │
              ──/api/v1/devices/{id}/events───▶ telemetry-service :3004 ─┼─▶ PostgreSQL (t1-loc-db, 스키마 dev)
              ──/api/v1/devices*──────────────▶ device-service    :3002 ─┘
              ──/simulator────────────────────▶ simulator         :3005
              ──/ ───────▶ web-nginx :80 ─────▶ web (Next.js)     :3000

control ──command publish──▶ MQTT(mosquitto :1883) ──▶ simulator (가상 가전 6종)
telemetry ◀──state/status subscribe── MQTT ◀── simulator
device-service ──meta publish(retained)──▶ MQTT  (등록한 기기를 시뮬레이터가 알게 함)
```

| 구성 요소 | 폴더 | 포트 | 하는 일 |
| --- | --- | --- | --- |
| auth-service | services/auth-service | 3001 | 회원가입·로그인·토큰 재발급·로그아웃, JWT(RS256) 발급, JWKS 제공 |
| device-service | services/device-service | 3002 | 기기 등록·조회·삭제, 현재 상태 조회, 등록 시 MQTT meta 발행 |
| control-service | services/control-service | 3003 | 기기 명령 발행 → 기기 응답 대기(5초) → 결과 응답, 엘리베이터 호출 |
| telemetry-service | services/telemetry-service | 3004 | state/status/command 구독 → 상태·이력 저장, 오프라인 판정, 이력 조회 API |
| simulator | services/simulator | 3005 | 가전 6종 가상 기기 + 대시보드 화면(/simulator). DB 접근 없음 |
| web | web | 3000 | Next.js 사용자 화면 (/login, /signup, /devices(기기 등록 창 포함), /devices/[id]) |
| web-nginx | nginx | 80→8080 | Envoy Gateway 뒤, Next.js 앞 (정적 파일 캐시) |
| dev-gateway | tools/dev-gateway | 8080 | **로컬 개발 전용** Gateway. Envoy 와 같은 경로 규칙 + JWT 검증 (클러스터에는 배포 안 함) |
| mosquitto | mosquitto | 1883 | MQTT 브로커 (계정 인증) |
| postgres | db/init | 5432 | 로컬: compose 컨테이너 / 클러스터: t1-loc-db |

공통 코드(설정·로그·에러 형식·사용자 식별·MQTT·지표·기기 명령 규칙)는 `packages/common` 에 있고, npm workspaces로 각 서비스가 같이 씁니다.

### 0-1. 인증 구조 — JWT 는 Gateway 에서만 검사

```
브라우저 ── Authorization: Bearer <Access 토큰> ──▶ Gateway

Gateway
  ① 바깥에서 온 x-user-id / x-user-email 헤더 삭제 (위조 방지)
  ② 보호 경로면 Access 토큰 검증
     (서명 RS256 · iss · aud · 만료) → 실패하면 401, 서비스로 안 보냄
  ③ 토큰 claim 을 헤더로 넣어 전달
     sub → x-user-id,  email → x-user-email
        │
        ▼
각 서비스
  - 토큰은 보지 않고 x-user-id 로 사용자 식별
  - x-user-id 가 없으면 401 (Gateway 를 거치지 않은 요청)
  - 서비스 간 호출(control·telemetry → device)도 x-user-id 를 그대로 전달
```

| 구분 | 클러스터 | 로컬 개발 (3·4절) |
| --- | --- | --- |
| Gateway | Envoy Gateway | `tools/dev-gateway` (Node.js, 외부 패키지 없음) |
| 토큰 검증 | SecurityPolicy `api-jwt` (`secrets/security-policy.yaml`, 공개키 JWKS 내장) | `secrets/jwt-public.pem` 으로 검증 |
| claim → 헤더 | SecurityPolicy `claimToHeaders` | dev-gateway 가 같은 헤더를 넣음 |
| 위조 헤더 삭제 | ClientTrafficPolicy `strip-user-headers` (`deploy/k8s/base/gateway-security.yaml`) | dev-gateway 가 모든 요청에서 삭제 |
| 서비스 직접 호출 차단 | NetworkPolicy (`deploy/k8s/base/networkpolicy.yaml`): Envoy · 내부 서비스에서 온 요청만 허용 | 개발 환경이라 차단하지 않음 |

토큰 종류:

| 토큰 | aud | 유효 기간 | 어디서 확인 |
| --- | --- | --- | --- |
| Access | `homeiot` | 1시간 | Gateway (보호 경로 전부) |
| Refresh | `homeiot-refresh` | 14일 | Gateway 는 거부 (aud 가 다름). `POST /auth/refresh` 에서 auth-service 가 재발급 절차로만 확인 |

- auth-service 는 토큰을 **발급**만 합니다 (개인키 `jwt-private.pem` 은 auth-service 만 가짐). 다른 서비스에는 키가 없습니다.
- 경로별 검증 여부는 9-1절 표, Gateway 경로 규칙은 `deploy/k8s/base/gateway.yaml` 과 `tools/dev-gateway/index.js` 의 `RULES` 가 같습니다. **경로를 바꾸면 두 곳을 같이 고칩니다.**

---

## 1. 서버와 주소

t1-base는 10.10.31.20, 나머지는 kubeadm 구축 가이드의 1팀 주소 규칙(`.10` DB, `.11~.13` 노드, `.100~.127` MetalLB)을 10.10.31.x 대역에 적용했습니다.
**IP나 이름이 바뀌면 1-1절 표의 위치만 고치면 됩니다.**

| VM | IP | 역할 |
| --- | --- | --- |
| t1-base | 10.10.31.20 | 개발 VM. 소스 편집, docker compose, git · gh, kubectl |
| t1-loc-db | 10.10.31.10 | PostgreSQL 16, DB `homeiot`, 스키마 `dev` |
| t1-loc-cp | 10.10.31.11 | control plane |
| t1-loc-w1 · t1-loc-w2 | 10.10.31.12 · .13 | 워커 |
| MetalLB 대역 | 10.10.31.100 ~ .127 | Envoy Gateway 외부 주소 |

확인: `hostname -I` (각 VM), `kubectl get nodes -o wide`

### 1-1. IP나 호스트 이름이 바뀔 때 고칠 곳

**t1-base** (개발 VM)

| 바뀐 것 | 고칠 곳 | 방법 | 다시 할 일 |
| --- | --- | --- | --- |
| t1-base IP | VM 네트워크 설정 `/etc/netplan/*.yaml` | `addresses: [10.10.31.20/24]` 를 새 IP로 → `sudo netplan apply` | `hostname -I` 로 확인 |
| t1-base IP | `.env` 의 `DEV_HOSTS` | `DEV_HOSTS=<새 IP>,t1-base` | `make web-dev` 다시 실행, `make urls` 로 주소 확인 |
| t1-base IP (Jenkins 를 쓰는 경우, 10절) | `ci/jenkins/.env` 의 `JENKINS_URL` | `JENKINS_URL=http://<새 IP>:8090/` | `make jenkins-up` 다시 실행 |
| t1-base IP가 10.10.31.0/24 밖으로 | t1-loc-db `pg_hba.conf` (`scripts/setup-t1-loc-db.sh` 의 `ALLOW_CIDR`) | `ALLOW_CIDR=<새 대역> DB_PASSWORD=… bash setup-t1-loc-db.sh` (6-1절) | t1-base에서 `psql -h 10.10.31.10 …` 접속 확인 |
| t1-base 이름 | 호스트 이름 | `sudo hostnamectl set-hostname <새 이름>` → `/etc/hosts` 의 `127.0.1.1 t1-base` 줄도 새 이름으로 | 다시 접속하면 프롬프트에 새 이름 |
| t1-base 이름 | `.env` 의 `DEV_HOSTS` | `DEV_HOSTS=10.10.31.20,<새 이름>` | `make web-dev` 다시 실행 |
| t1-base 이름 (이름으로 접속하는 경우) | 접속하는 PC의 hosts 파일 (Windows: `C:\Windows\System32\drivers\etc\hosts`, 관리자 권한) | `10.10.31.20  <새 이름>` 한 줄 | 브라우저에서 `http://<새 이름>:3000` |

t1-base IP·이름은 **클러스터 매니페스트, GitHub Actions, Jenkinsfile, Argo CD 어디에도 들어 있지 않습니다**. 위 표 외에는 고칠 곳이 없습니다. 방법 B(`make up`)의 컨테이너는 모든 주소에서 접속을 받으므로 설정 변경 없이 새 IP로 접속하면 됩니다.

**다른 VM**

| 바뀐 것 | 고칠 곳 | 반영 |
| --- | --- | --- |
| t1-loc-db IP | `deploy/local.env` 의 `DB_IP` (make db-migrate 가 사용) | 바로 |
| t1-loc-db IP | `deploy/k8s/overlays/gitops/postgres-external.yaml` 의 `addresses` | main 에 커밋 → Argo CD 자동 반영 |
| t1-loc-db IP (로컬 개발에서 t1-loc-db를 쓰는 경우) | `.env` 의 `DB_HOST` | `make dev` 다시 실행 |
| t1-loc-cp IP | t1-base `~/.kube/config` 의 `server: https://<IP>:6443` | 단, API 서버 인증서에 새 IP가 없으면 클러스터 재구성 필요 (구축 가이드 12단계) |
| 노드 대역 전체 | t1-loc-db `ALLOW_CIDR` (6-1절), MetalLB 풀(구축 가이드 7단계) | 각 절차 다시 실행 |

---

## 2. t1-base 초기화

소스는 t1-base에 직접 가져와서 개발하고, t1-base에서 GitHub 저장소(`sooyeong-lee/home-iot`)로 올립니다.

### 2-1. 소스 가져오기

전달받은 `home-iot.zip` 을 t1-base로 옮기고 압축을 풉니다.

```bash
# Windows PC (PowerShell) 에서 t1-base 로 복사
scp .\home-iot.zip lab@10.10.31.20:~

# t1-base 에서
sudo apt-get install -y unzip
cd ~ && unzip home-iot.zip           # ~/home-iot 폴더가 생김
cd ~/home-iot && ls                  # Makefile, services/, web/, docs/ … 확인
```

> 이미 `~/home-iot` 가 있으면 덮어쓰지 말고 다른 이름으로 풀어서(`unzip home-iot.zip -d ~/tmp`) 비교한 뒤 옮기세요.

### 2-2. 개발 도구 설치 (한 번만)

```bash
cd ~/home-iot
bash scripts/setup-t1-base.sh
newgrp docker        # 또는 로그아웃 후 다시 접속 (docker 그룹 적용)
```

설치되는 것: Docker + compose + buildx, Node.js 22, kubectl v1.37, git, gh, psql, mosquitto-clients, jq, make.
t1-loc-cp의 `~/.kube/config` 를 복사해서 t1-base에서 `kubectl` 을 바로 쓸 수 있게 합니다 (IP가 다르면 `CP_IP=… bash scripts/setup-t1-base.sh`).

확인:

```bash
docker run --rm hello-world
node -v                                  # v22.x
kubectl get nodes                        # t1-loc-cp, t1-loc-w1, t1-loc-w2 Ready
```

### 2-3. GitHub 저장소로 올리기 (처음 한 번)

**① GitHub 로그인 · 작성자 설정**

```bash
gh auth login                            # GitHub.com → HTTPS → Yes → Login with a web browser
gh auth status                           # Logged in to github.com account sooyeong-lee
git config --global user.name  "sooyeong-lee"
git config --global user.email "<GitHub 계정 이메일>"
```

**② 로컬 소스를 git 저장소로 만들기**

```bash
cd ~/home-iot
git init -b main
git add -A
git status --short | grep -E '\.env$|secrets/|local\.env$' || echo "비밀 파일 없음"   # '비밀 파일 없음' 이 나와야 정상
git commit -m "feat: Home IoT MSA 초기 소스"
```

**③ 원격 저장소 연결 후 push**

GitHub 저장소에는 이미 `Initial commit`(README.md) 이 있어서, 그 커밋과 합친 뒤 올립니다. 겹치는 README.md 는 로컬 내용으로 둡니다.

```bash
git remote add origin https://github.com/sooyeong-lee/home-iot.git
git fetch origin
git merge origin/main --allow-unrelated-histories -X ours -m "merge: GitHub 초기 커밋과 합치기"
git push -u origin main
git log --oneline -3                     # 내 커밋 + merge 커밋 + Initial commit
```

브라우저에서 `https://github.com/sooyeong-lee/home-iot` 를 열어 파일이 올라갔는지 확인합니다.

> - 원격 저장소가 완전히 비어 있으면(커밋 없음) `git fetch`/`git merge` 없이 바로 `git push -u origin main` 합니다.
> - main 에 push 하면 GitHub Actions(`ci-cd`)가 바로 실행됩니다. 7-2절 ②(Workflow permissions: Read and write)를 먼저 해 두지 않았다면 마지막 `배포 매니페스트 갱신` 단계가 403 으로 실패합니다. 설정 후 `gh run rerun --failed` 로 다시 실행하면 됩니다. Jenkins 를 쓸 거라면 push 전에 10-5절대로 Actions 를 꺼 두세요.
> - 이후의 수정은 9-5절(브랜치 → PR → merge) 방식으로 올립니다.

### 2-4. 프로젝트 준비

```bash
make setup
```

- `.env` (로컬 개발 값), `deploy/local.env` (클러스터 Secret · DB 값) 를 예제에서 복사
  - `.env` 의 `DEV_HOSTS` 가 t1-base 주소(`10.10.31.20,t1-base`)인지 확인 — 다르면 1-1절
- `secrets/jwt-private.pem`, `secrets/jwt-public.pem`, `secrets/jwks.json` 생성 (RS256)
- `npm install` (백엔드 workspaces), `cd web && npm install`

> `.env`, `deploy/local.env`, `secrets/` 는 `.gitignore` 에 들어 있습니다. 비밀번호·키를 커밋하지 마세요.

---

## 3. 로컬 개발 (방법 A — 코드 수정이 바로 반영되는 방식, 권장)

DB와 MQTT만 컨테이너로 띄우고, 서비스와 개발용 게이트웨이는 t1-base에서 직접 실행합니다. 파일을 저장하면 자동으로 다시 시작합니다(`node --watch`, Next.js dev).

```bash
# 터미널 1: 인프라
make infra                 # postgres(5432) + mosquitto(1883)
docker compose ps          # 둘 다 running / healthy

# 터미널 2: 백엔드 5개 + dev-gateway(:8080, JWT 검증)
make dev                   # 로그 앞에 [서비스명]이 붙어서 한 화면에 나옴

# 터미널 3: 화면
make web-dev               # http://10.10.31.20:3000
```

- 접속 주소는 `make urls` 로도 볼 수 있습니다.
- 화면: `http://10.10.31.20:3000` (Next.js 개발 서버가 `/api/v1/*` 를 dev-gateway(:8080)로 전달 → dev-gateway 가 JWT 검증 후 각 서비스로 — `web/next.config.mjs`)
- API 를 curl 로 확인할 때도 dev-gateway 로 보냅니다: `curl http://localhost:8080/api/v1/devices -H "Authorization: Bearer <토큰>"`
  서비스 포트(3001~3004)로 직접 보내면 `x-user-id` 가 없어서 401 이 나는 것이 정상입니다.
- 시뮬레이터: `http://10.10.31.20:3005/simulator/`
- 서비스 하나만 다시 띄우기: `npm run dev:control` 처럼 `dev:auth | dev:device | dev:control | dev:telemetry | dev:simulator`
- `make dev` 로 띄운 상태에서는 `make smoke` 도 그대로 동작합니다 (dev-gateway 가 8080).
- 로컬 DB 대신 t1-loc-db를 쓰려면 `.env` 에서 `DB_HOST=10.10.31.10`, `DB_PASSWORD=…` 로 바꿉니다 (6절의 DB 준비가 먼저 필요).

DB 직접 보기:

```bash
make db-shell
homeiot=> \dt
homeiot=> SELECT device_id, status, last_seen_at FROM devices;
```

MQTT 메시지 직접 보기:

```bash
mosquitto_sub -h localhost -u homeiot -P homeiot-dev -t 'home/#' -v
```

### 화면으로 동작 확인 (조명 켜기 시나리오)

1. `/signup` 에서 가입 → `/login` 으로 로그인
2. `/devices` 에서 **+ 기기 등록** → 같은 화면에 등록 창이 열림 → 기기 종류 드롭다운에서 **조명** 선택 → 설치 위치 `거실` (이름은 `거실 조명` 으로 자동 입력) → **등록하기**. 기기 ID는 `light-<사용자ID>-01` 처럼 자동으로 만들어지고, 창이 닫히면서 목록 위 알림에 표시됩니다
3. 시뮬레이터 화면에 같은 기기가 생기고, 몇 초 안에 사용자 화면 카드가 **온라인** 으로 바뀜
4. 카드의 **상세 보기 →** → **켜기** / 밝기 **+**
5. 시뮬레이터 이벤트 로그에 `command` 수신 → `state` 발행이 찍히고, 상세 화면 상태·최근 이벤트가 바뀜
6. 커튼은 대시보드에서 바로 **열기/닫기**, 엘리베이터는 층을 넣고 **호출** → 시뮬레이터에서 층 이동 후 도착 (**도착 처리** 버튼으로 바로 도착시킬 수도 있음)

오류 재현:

| 확인하고 싶은 것 | 방법 | 기대 결과 |
| --- | --- | --- |
| 기기 오프라인 409 | 시뮬레이터에서 **연결 끊기** → 약 20초 뒤 제어 | "기기가 오프라인 상태입니다." |
| 기기 응답 없음 504 | **연결 끊기** 직후(20초 안에) 제어 | 5초 뒤 "기기로부터 응답이 없습니다." |
| 손으로 조작 | 시뮬레이터 **상태 변경** → 값 수정 → 적용 | 사용자 화면이 3초 안에 바뀜, 이력에 STATE_CHANGED |

---

## 4. 로컬 개발 (방법 B — 클러스터와 같은 이미지로 전부 컨테이너 실행)

이미지·Dockerfile을 확인하거나, 배포 전에 한 번에 띄워 볼 때 씁니다.

```bash
make up                    # docker compose --profile app up -d --build
docker compose --profile app ps
make smoke                 # 자동 흐름 확인 (http://localhost:8080)
make logs                  # 로그
make down                  # 중지
```

- 화면: `http://10.10.31.20:8080` / 시뮬레이터: `http://10.10.31.20:8080/simulator/`
- 8080의 dev-gateway(`tools/dev-gateway`)가 클러스터의 Envoy Gateway와 **같은 경로 규칙**으로 요청을 나누고, 보호 경로의 JWT 를 검증합니다.
- 방법 A와 동시에 띄우면 포트가 겹칩니다. 하나만 쓰세요 (`make down` 후 `make infra`).

`make smoke` 가 확인하는 것: 가입·중복 가입 409 → 로그인 → 토큰 없는 요청 401 → 위조 `x-user-id` 헤더만으로 401 → Refresh 토큰으로 API 호출 401 → 조명·엘리베이터 등록 → 기기 ID 자동 생성 → online 전환 → 조명 켜기(명령·응답) → 범위 오류 400 → 미지원 명령 422 → 상태 저장 → 이력(COMMAND_SENT, STATE_CHANGED) → 엘리베이터 호출 202 → 중복 호출 409 → 도착 → 정리

DB 초기화: `make db-reset` (로컬 postgres 볼륨 삭제 후 `db/init/01_schema.sql` 로 다시 만듦)

---

## 5. 단위 테스트

```bash
make test        # packages/common 의 기기 명령 검증·토픽 규칙 테스트 (node:test)
```

---

## 6. t1-loc-db 준비 (클러스터 배포 전 한 번)

### 6-1. PostgreSQL 설치·접속 허용 (t1-loc-db에서)

```bash
# t1-base 에서 스크립트를 보내고 실행
scp scripts/setup-t1-loc-db.sh lab@10.10.31.10:~
ssh -t lab@10.10.31.10 'DB_PASSWORD=<deploy/local.env 의 DB_PASSWORD> bash ~/setup-t1-loc-db.sh'
```

하는 일: PostgreSQL 설치(없을 때만), `listen_addresses='*'`, `pg_hba.conf` 에 `10.10.31.0/24` 허용, 계정 `homeiot` · DB `homeiot` 생성.
파드가 DB로 나갈 때 출발 주소는 노드 IP(10.10.31.11~13)로 바뀌므로(Calico natOutgoing) 이 대역만 허용하면 됩니다.

### 6-2. 테이블 생성 (t1-base에서)

```bash
make db-migrate          # db/init/01_schema.sql → 스키마 dev 에 테이블 8개
psql -h 10.10.31.10 -U homeiot -d homeiot -c '\dt dev.*'
```

`01_schema.sql` 은 `IF NOT EXISTS` 로 작성되어 여러 번 실행해도 됩니다.

---

## 7. 로컬 클러스터 배포 — GitHub Actions + Argo CD (GitOps)

### 7-1. 전체 흐름

```
개발자 ──PR──▶ GitHub (sooyeong-lee/home-iot)
                 │ PR       : 테스트 · 이미지 빌드 · Trivy 검사 (push 안 함)
                 │ merge    : main 에 들어오면
                 ▼
          GitHub Actions (.github/workflows/ci-cd.yml)
            1) test            단위 테스트 · JS 문법 · kustomize 렌더링
            2) build (7개)     docker build → Trivy(CRITICAL 이면 실패) → GHCR push
                               ghcr.io/sooyeong-lee/home-iot/<서비스>:sha-xxxxxxx, :latest
            3) update-manifest deploy/k8s/overlays/gitops/kustomization.yaml 의
                               newTag 를 sha-xxxxxxx 로 바꿔 main 에 커밋
                 │
                 ▼
          Argo CD (로컬 클러스터 argocd 네임스페이스)
            main 의 deploy/k8s/overlays/gitops 를 감시 (기본 3분 주기)
            → 바뀐 태그로 homeiot 네임스페이스에 자동 동기화 (prune · selfHeal)
                 │
                 ▼
          t1-loc-w1 / w2 가 GHCR 에서 이미지를 받아 롤링 업데이트
```

| 파일 | 역할 |
| --- | --- |
| `.github/workflows/ci-cd.yml` | CI/CD 파이프라인 |
| `deploy/k8s/overlays/gitops/` | Argo CD가 읽는 매니페스트 (GHCR 이미지, DB IP 고정, pull Secret 연결) |
| `deploy/argocd/application.yaml` | Argo CD Application (`home-iot`) |
| `scripts/argocd-install.sh` | Argo CD 설치 + LoadBalancer 노출 |
| `scripts/ghcr-pull-secret.sh` | GHCR 비공개 이미지 pull Secret |
| `scripts/argocd-repo-secret.sh` | 비공개 저장소일 때 Argo CD 저장소 자격증명 |

> CI 를 GitHub Actions 대신 Jenkins 로 하려면 10절을 봅니다. Argo CD 부분은 같습니다.

### 7-2. 사전 준비 (처음 한 번)

**⓪ t1-loc-db 준비(6절)가 끝났는지 확인**

**① 클러스터 노드에서 인터넷(ghcr.io) 접속 확인**

```bash
ssh lab@10.10.31.12 'curl -sI https://ghcr.io | head -1'     # HTTP/2 405 등 응답이 오면 됨
```

**② GitHub 저장소 설정** — `https://github.com/sooyeong-lee/home-iot` → **Settings**

| 메뉴 | 설정 | 이유 |
| --- | --- | --- |
| Actions → General → Workflow permissions | **Read and write permissions** 선택 → Save | update-manifest 잡이 main 에 태그 커밋 |
| Branches (branch protection 을 쓰는 경우) | `github-actions[bot]` 이 main 에 push 할 수 있게 허용 (또는 보호 규칙의 bypass 목록에 추가) | 막혀 있으면 update-manifest 가 `protected branch` 오류 |

**③ GitHub 토큰(PAT) 만들기** — GitHub 오른쪽 위 프로필 → **Settings → Developer settings → Personal access tokens → Tokens (classic) → Generate new token**

| 용도 | 권한(scope) | 필요한 경우 |
| --- | --- | --- |
| 클러스터가 GHCR 이미지 받기 | `read:packages` | GHCR 패키지가 비공개일 때 (기본값) |
| Argo CD가 저장소 읽기 | `repo` | 저장소가 비공개일 때 |

> 토큰은 화면에 한 번만 보입니다. 채팅·저장소에 붙이지 말고 아래 명령에 환경 변수로만 넘깁니다.
> GHCR 패키지를 공개로 바꾸면 pull 토큰이 필요 없습니다: 첫 빌드 후 GitHub 프로필 → **Packages** → 각 패키지 → **Package settings → Change visibility → Public**.

### 7-3. 첫 빌드 확인

2-3절에서 소스를 main 에 push 하면 첫 실행이 시작됩니다. (그 뒤로는 PR 을 만들 때마다 검사, merge 할 때마다 배포)

1. 저장소 **Actions** 탭 → `ci-cd` 실행에서 `테스트`, `이미지 …` 7개, `배포 매니페스트 갱신` 이 모두 초록색인지 확인
2. 이후 PR 에서는 push 없이 빌드·검사만, main 에 merge 하면 GHCR push 와 매니페스트 갱신까지 진행
3. 확인

```bash
gh run list --limit 5                        # ci-cd 가 completed / success
gh run watch                                 # 진행 중인 실행 지켜보기
git pull && git log --oneline -3             # "chore(deploy): 이미지 sha-xxxxxxx 배포" 커밋이 생김
grep newTag deploy/k8s/overlays/gitops/kustomization.yaml
```

GHCR 확인: GitHub 프로필 → **Packages** 에 `home-iot/auth-service` 등 7개.

> 처음 main 에 올라간 커밋에서 Trivy가 CRITICAL 취약점을 찾으면 build 가 실패합니다. 로그의 표에서 패키지를 확인하고 베이스 이미지를 올리거나(예: `node:22-alpine` 최신 태그로 다시 빌드) 의존성 버전을 올립니다.

### 7-4. Argo CD 설치 (t1-base에서)

구축 가이드 9단계까지 끝난 클러스터(MetalLB · Envoy Gateway 설치됨)를 기준으로 합니다.

```bash
make argocd-install
# Argo CD 설치 완료
#   화면    : https://10.10.31.10x
#   계정    : admin
#   비밀번호: xxxxxxxx
```

- 브라우저에서 화면 주소로 접속 → 인증서 경고는 **고급 → 계속**
- 로그인 후 **User Info → UPDATE PASSWORD** 로 비밀번호를 바꾸고 초기 비밀번호 Secret 삭제:
  `kubectl -n argocd delete secret argocd-initial-admin-secret`
- 버전을 고정하려면: `ARGOCD_VERSION=v3.x.y make argocd-install` ([릴리스 목록](https://github.com/argoproj/argo-cd/releases)에서 확인)

비공개 저장소라면 저장소 자격증명 등록:

```bash
GITHUB_USER=sooyeong-lee GITHUB_TOKEN=<repo 권한 PAT> bash scripts/argocd-repo-secret.sh
```

### 7-5. 배포 Secret 준비 (git 에 넣지 않는 값)

```bash
GHCR_USER=sooyeong-lee GHCR_TOKEN=<read:packages PAT> make gitops-secrets
kubectl -n homeiot get secret                # homeiot-secrets, homeiot-jwt, ghcr-pull
```

`make gitops-secrets` 가 하는 일:

1. `homeiot-secrets` (DB·MQTT 계정, `deploy/local.env` 값), `homeiot-jwt` (`secrets/jwt-private.pem`, auth-service 토큰 발급용)
2. `ghcr-pull` (GHCR pull 토큰)
3. Envoy Gateway JWT 정책 `secrets/security-policy.yaml` 적용 — 공개키(JWKS)와 claim → 헤더(`x-user-id`, `x-user-email`) 설정이 들어 있음. Argo CD 관리 대상이 아니므로 키를 바꾸면 다시 실행

> **이 정책이 없으면 보호 경로가 모두 401 입니다.** 토큰 검증을 Gateway 에서만 하므로, 정책이 없으면 서비스에 `x-user-id` 가 오지 않아 서비스가 401 을 돌려줍니다 (토큰 없이 통과되는 일은 없음).

DB IP가 10.10.31.10이 아니면 `deploy/k8s/overlays/gitops/postgres-external.yaml` 을 고쳐서 main 에 커밋합니다.

### 7-6. Application 등록 → 자동 배포 시작

```bash
make argocd-app                              # deploy/argocd/application.yaml 적용
make argocd-status                           # Synced / Healthy / <커밋 sha>
kubectl -n homeiot get pods -o wide
kubectl -n homeiot get deploy -o custom-columns=NAME:.metadata.name,IMAGE:.spec.template.spec.containers[0].image
```

Argo CD 화면에서 `home-iot` 카드 → 리소스 트리(Deployment → ReplicaSet → Pod)가 모두 초록색이면 완료입니다.

동작 확인:

```bash
BASE_URL=http://$(kubectl -n homeiot get gateway homeiot-gw -o jsonpath='{.status.addresses[0].value}') make smoke
```

Gateway 에서만 JWT 를 검사하는 구성이 제대로 적용됐는지 확인:

```bash
# ① Gateway 정책이 받아들여졌는지 (Accepted True)
kubectl -n homeiot get securitypolicy,clienttrafficpolicy
kubectl -n homeiot describe securitypolicy api-jwt | grep -A3 Conditions

# ② Gateway 를 건너뛰고 서비스에 직접 요청하면 막히는지 (NetworkPolicy)
kubectl -n homeiot run nettest --rm -i --image=busybox:1.37 --restart=Never -- \
  wget -qO- -T 3 --header 'x-user-id: 1' http://device-service:3002/api/v1/devices
#   → "download timed out" 이면 정상 (막힘). 기기 목록이 나오면 NetworkPolicy 가 적용되지 않은 것
```

`make smoke` 의 "위조 x-user-id 헤더만으로 401", "Refresh 토큰으로 API 호출 401" 항목이 Gateway 검증을 확인합니다.

### 7-7. 평소 개발 흐름

```bash
git switch main && git pull
git switch -c feature/<작업>
# … 수정 · make dev / make up 으로 로컬 확인 · make smoke …
git add -A && git commit -m "feat: …" && git push -u origin feature/<작업>
gh pr create --base main                    # Checks 통과 확인 → 리뷰 → Merge
```

merge 후 약 5~10분 안에 (Actions 빌드 + Argo CD 감지 주기 3분) 클러스터에 반영됩니다. 바로 반영하려면 Argo CD 화면에서 **REFRESH → SYNC**, 또는:

```bash
kubectl -n argocd annotate application home-iot argocd.argoproj.io/refresh=hard --overwrite
```

### 7-8. 되돌리기 (롤백)

git 이 기준이므로 태그 변경 커밋을 되돌리면 됩니다.

```bash
git pull
git log --oneline -- deploy/k8s/overlays/gitops/kustomization.yaml    # 태그 변경 이력
git revert <되돌릴 chore(deploy) 커밋>                                 # 이전 sha 태그로 복귀
git push origin main                                                    # → Argo CD 가 이전 이미지로 동기화
```

> Argo CD 화면의 **HISTORY AND ROLLBACK** 도 쓸 수 있지만 자동 동기화가 켜져 있으면 곧 git 상태로 돌아갑니다. 롤백은 git revert 로 하세요.

### 7-9. 막혔을 때 (파이프라인 · Argo CD)

| 증상 | 확인 | 해결 |
| --- | --- | --- |
| Actions `update-manifest` 가 `403` / `Permission to … denied` | Settings → Actions → Workflow permissions | **Read and write permissions** |
| `update-manifest` 가 `protected branch hook declined` | 브랜치 보호 규칙 | bot 을 bypass 목록에 추가하거나 규칙 조정 |
| build 가 Trivy 단계에서 실패 | 로그의 CRITICAL 표 | 베이스 이미지·의존성 버전 올림 |
| 파드 `ImagePullBackOff`, `401 Unauthorized` / `denied` | `kubectl -n homeiot describe pod …` | `ghcr-pull` Secret 토큰 권한(`read:packages`) 확인 → `make gitops-secrets`, 또는 패키지 Public |
| 파드 `ImagePullBackOff`, `i/o timeout` | 노드에서 `curl -sI https://ghcr.io` | 노드의 인터넷·DNS 확인 |
| Argo CD `ComparisonError` / `repository not found` | Settings → Repositories | 비공개 저장소 → `scripts/argocd-repo-secret.sh` |
| Argo CD `Unknown` / `kustomize build failed` | 화면의 오류 메시지 | 로컬에서 `kubectl kustomize deploy/k8s/overlays/gitops` 로 같은 오류 재현 후 수정 |
| `OutOfSync` 가 계속 | **APP DIFF** | 클러스터에서 손으로 바꾼 값 → selfHeal 이 되돌림. 원하는 값은 git 에 커밋 |
| 파드 `CreateContainerConfigError` (`secret "homeiot-secrets" not found`) | `kubectl -n homeiot get secret` | 7-5 다시 실행 |
| 새 커밋을 merge 했는데 그대로 | `make argocd-status` 의 sha, Actions 실행 결과 | Actions 성공·태그 커밋 확인 → Argo CD **REFRESH** |

---

## 8. 막혔을 때

| 증상 | 확인 | 해결 |
| --- | --- | --- |
| `make dev` 에서 `[dev-gateway] JWT_PUBLIC_KEY_FILE` 오류 · `[auth-service] JWT_PRIVATE_KEY ... 필요` | `ls secrets/` | `make setup` 또는 `bash scripts/gen-jwt-keys.sh` |
| 서비스 포트(3001~3004)로 직접 호출하면 401 | 요청 주소 | 정상. Gateway(로컬 :8080, 클러스터 Gateway 주소)를 통해 호출 |
| 로그인은 되는데 다른 API 가 모두 401 (클러스터) | `kubectl -n homeiot get securitypolicy api-jwt` | 없으면 `make gitops-secrets` (7-5). 있으면 `kubectl -n homeiot describe securitypolicy api-jwt` 의 Conditions 확인 |
| 로그인 직후 API 가 `Jwt verification fails` 401 (클러스터) | 키를 다시 만들었는지 | 정책의 공개키와 auth-service 개인키가 다름 → `make gitops-secrets` → `kubectl -n homeiot rollout restart deploy/auth-service` 후 다시 로그인 |
| Envoy 로그에 `upstream connect error` / 503 | `kubectl -n envoy-gateway-system get pods` 위치 | NetworkPolicy 는 Envoy 파드가 `envoy-gateway-system` 에 있다고 가정. 다른 곳이면 `deploy/k8s/base/networkpolicy.yaml` 의 namespaceSelector 수정 |
| 서비스 로그에 `ECONNREFUSED 127.0.0.1:5432` | `docker compose ps` | `make infra` |
| `mqtt reconnecting` 이 계속 | mosquitto 로그 `docker compose logs mosquitto` | `.env` 의 MQTT 계정이 compose 값과 같은지 확인 |
| `make web-dev` 화면이 안 바뀜 · 터미널에 `Blocked cross-origin request` | 브라우저 주소의 IP·이름 | `.env` 의 `DEV_HOSTS` 에 그 주소 추가 → `make web-dev` 다시 실행 (1-1절) |
| 다른 PC에서 접속 안 됨 | t1-base에서 `sudo ufw status` | active면 `sudo ufw allow 3000,3005,8080/tcp` |
| 기기가 계속 오프라인 | 시뮬레이터 화면에 기기가 있는지 | 시뮬레이터 실행 확인. 없으면 device-service 재시작(등록 기기 meta 재발행) |
| 제어하면 504 | 시뮬레이터 이벤트 로그에 command 수신이 있는지 | 시뮬레이터에서 **다시 연결** |
| 파드 `CrashLoopBackOff`, 로그에 `password authentication failed` | `kubectl -n homeiot logs deploy/auth-service` | `deploy/local.env` 의 DB 값과 t1-loc-db 계정이 같은지 → `make gitops-secrets` → `kubectl -n homeiot rollout restart deploy` |
| DB 연결 타임아웃 | t1-base에서 `psql -h 10.10.31.10 -U homeiot -d homeiot` | t1-loc-db `pg_hba.conf`·`listen_addresses` (6-1 다시 실행) |
| Gateway ADDRESS가 비어 있음 | `kubectl get ipaddresspool -n metallb-system` | 구축 가이드 7단계 MetalLB 풀(10.10.31.100-127) |
| `/api/v1/devices/{id}/commands` 가 404 | `kubectl -n homeiot logs deploy/device-service` 에 commands 요청이 찍힘 | HTTPRoute `api` 의 정규식 규칙 확인: `kubectl -n homeiot describe httproute api` |
| `security-policy.yaml` 적용 오류 | `kubectl get crd securitypolicies.gateway.envoyproxy.io` | Envoy Gateway 설치 확인. 정책 없이도 각 서비스가 JWT를 직접 검증하므로 기능은 동작 |
| Envoy가 401 `Jwt issuer is not configured` / `Jwks remote fetch failed` | 키를 다시 만들었는지 | `make gitops-secrets` 로 Secret 과 정책을 같은 키로 다시 적용 → `kubectl -n homeiot rollout restart deploy` |

로그는 모두 JSON 한 줄 형식입니다: `kubectl -n homeiot logs deploy/control-service | jq -r '[.time,.level,.msg,.commandId] | @tsv'`

---

## 9. 참고

### 9-1. API 라우팅 (Envoy HTTPRoute = tools/dev-gateway)

'Gateway JWT 검증' 이 필요인 경로는 Gateway 가 Access 토큰을 검증하고 `x-user-id` 를 붙여 보냅니다. 서비스는 토큰을 검사하지 않습니다.

| 경로 | 서비스 | Gateway JWT 검증 |
| --- | --- | --- |
| POST /api/v1/auth/signup · login · refresh, GET /api/v1/auth/.well-known/jwks.json | auth | 불필요 |
| POST /api/v1/auth/logout, GET /api/v1/users/me | auth | 필요 |
| POST /api/v1/devices/{id}/commands | control | 필요 |
| POST /api/v1/elevator/calls, GET /api/v1/elevator/calls/{callId} | control | 필요 |
| GET /api/v1/devices/{id}/events | telemetry | 필요 |
| GET·POST /api/v1/devices, GET·DELETE /api/v1/devices/{id}, GET /api/v1/devices/{id}/state | device | 필요 |
| /simulator | simulator | 없음 (테스트 도구, NetworkPolicy 로 Gateway 경유만 허용) |
| / | web-nginx → web | 없음 |

### 9-2. MQTT 토픽 (homeId = 기기 소유자 user_id)

| 토픽 | 방향 | 내용 |
| --- | --- | --- |
| home/{homeId}/devices/{deviceId}/command | control → 기기 | `{commandId, command, params}` |
| home/{homeId}/devices/{deviceId}/state | 기기 → control·telemetry | `{commandId?, power, state, reportedAt}` / 실패 시 `{commandId, error}` |
| home/{homeId}/devices/{deviceId}/status | 기기 → telemetry | `{status: online|offline}` |
| home/{homeId}/devices/{deviceId}/meta | device → 기기 (retained) | `{deviceId, type, name, location}` — **추가 토픽** |
| home/{homeId}/elevator/call | control → 엘리베이터 | `{callId, deviceId, floor, direction}` |
| home/{homeId}/elevator/status | 엘리베이터 → control | `{callId, status, currentFloor}` |

### 9-3. 관측

모든 서비스가 `/metrics`(Prometheus), `/healthz`(liveness), `/readyz`(DB·MQTT 연결 확인)를 제공합니다.
업무 지표: `homeiot_commands_total{type,command,result}`, `homeiot_command_roundtrip_seconds`, `homeiot_mqtt_messages_total`, `homeiot_devices_online`.
파드에는 `prometheus.io/scrape` 어노테이션이 붙어 있습니다.

### 9-4. 설계 문서와 달라진 점 · 보완한 점

| 항목 | 설계 문서 | 구현 | 이유 |
| --- | --- | --- | --- |
| DB 구성 | 서비스별 DB 분리(아키텍처) | PostgreSQL 하나, 스키마 `dev` 하나 | 팀 결정 사항. 서비스 경계를 넘는 조회는 REST(device-service)로 함 |
| devices.location | 없음 | `VARCHAR(50)` 추가 | 와이어프레임 기기 등록의 "설치 위치" |
| 기기 등록 API | API 명세 목록에 없음 | `POST /devices`, `DELETE /devices/{id}` 추가 | 와이어프레임·요구사항 US-03/US-06 |
| 기기 등록 화면 | 별도 화면 `/devices/new`, 기기 종류 드롭다운 + 기기 ID 직접 입력 | 별도 페이지 없이 기기 현황 화면(`/devices`) 위에 뜨는 등록 창, 종류는 드롭다운 그대로, 기기 ID 는 서버가 `<종류>-<사용자ID>-<순번>` 으로 자동 생성 (예: `light-5-01`). API 로 `deviceId` 를 직접 보내면 그 값을 사용 | 입력 실수·중복 방지 |
| 409 코드 | EMAIL_DUPLICATED, DEVICE_OFFLINE | `DEVICE_DUPLICATED`, `ELEVATOR_ALREADY_CALLED` 추가 | 기기 ID 를 직접 지정했을 때 중복 409, DB 명세 중복 호출 409 |
| 422 코드 | UNSUPPORTED_COMMAND | `COMMAND_FAILED` 추가 | 기기가 명령 처리에 실패한 경우 |
| MQTT meta 토픽 | 없음 | retained 메시지로 추가 | 시뮬레이터가 DB 없이 등록 기기를 알기 위해 |
| 엘리베이터 호출 | `{floor, direction}` | `deviceId` 선택 필드 추가 (없으면 첫 엘리베이터) | 기기가 여러 대일 때 구분 |
| 엘리베이터 대시보드 | `POST /devices/{id}/command {action: call}` (와이어프레임) | `POST /elevator/calls` | API 명세서가 최신 |
| JWT | 미정 | RS256, Access 1시간 · Refresh 14일(회전). **검증은 Gateway 에서만**, 서비스는 `x-user-id` 헤더로 식별, NetworkPolicy 로 서비스 직접 호출 차단 (0-1절) | 검증 위치를 한 곳으로 모으고, 서비스에는 키를 두지 않기 위해 |
| simulators 테이블 | 시뮬레이터 설정 | 테이블만 생성, 미사용 | 와이어프레임: 시뮬레이터는 DB에 접근하지 않음 |
| 상태 갱신 방식 | 결정 필요 | 3초 주기 조회 | 단순한 쪽 먼저. 서버 푸시는 이후 결정 |

### 9-5. GitHub에 브랜치 push · PR 만들기

2-3절에서 처음 올린 뒤, 수정한 내용을 브랜치로 `sooyeong-lee/home-iot` 에 올리고 PR(Pull Request)을 만드는 절차입니다. 1)·2)는 2-3절에서 했다면 건너뜁니다.

**1) GitHub 로그인 (처음 한 번)**

```bash
gh auth login
#  ? Where do you use GitHub?            → GitHub.com
#  ? What is your preferred protocol?    → HTTPS
#  ? Authenticate Git with your GitHub credentials? → Yes
#  ? How would you like to authenticate? → Login with a web browser
#    (화면의 8자리 코드를 https://github.com/login/device 에 입력)
gh auth status                       # Logged in to github.com account sooyeong-lee
```

**2) 커밋 작성자 설정 (처음 한 번)**

```bash
git config --global user.name  "sooyeong-lee"
git config --global user.email "<GitHub 계정 이메일>"
```

**3) 브랜치 만들고 커밋**

```bash
cd ~/home-iot
git switch main && git pull                 # 최신 main 받기
git switch -c feature/<작업 이름>            # 예: feature/light-dimming
# … 코드 수정 …
git status                                  # .env, secrets/, deploy/local.env 가 목록에 없어야 함
git add -A
git commit -m "feat: <무엇을 바꿨는지>"
```

**4) 브랜치 push**

```bash
git push -u origin feature/<작업 이름>
# 이후 같은 브랜치에서 추가 커밋은 git push 만 하면 됨
```

**5) PR 만들기**

```bash
gh pr create --base main --head feature/<작업 이름> \
  --title "feat: Home IoT MSA 로컬 개발/배포 구성" \
  --body "변경 내용 / 확인 방법(make smoke 결과) / 참고 사항"
gh pr view --web                            # 브라우저에서 PR 열기
```

웹으로 만들려면: push 후 https://github.com/sooyeong-lee/home-iot 에 들어가면 나오는 **Compare & pull request** 버튼 → base `main`, compare `feature/<작업 이름>` 확인 → 제목·설명 입력 → **Create pull request**.

**6) 리뷰 반영 · 병합**

```bash
# 리뷰 의견 반영: 같은 브랜치에서 수정 → 커밋 → push 하면 PR에 자동으로 붙음
git add -A && git commit -m "fix: 리뷰 반영" && git push

gh pr status                                # 내 PR 상태
gh pr merge --squash --delete-branch        # 병합 후 원격 브랜치 삭제
git switch main && git pull                 # 로컬 main 최신화
```

| 증상 | 해결 |
| --- | --- |
| push 시 `Permission denied` / `403` | `gh auth status` 확인 → `gh auth login` 다시, 저장소 쓰기 권한 확인 |
| push 시 `rejected (fetch first)` | `git pull --rebase origin feature/<작업 이름>` 후 다시 push |
| PR에 `.env` 나 `secrets/` 가 보임 | `git rm --cached -r secrets .env` → 커밋 → push, 노출된 비밀번호·키는 새로 만들기 (`make keys`) |

### 9-6. 스크립트(.sh) 설명

모든 스크립트는 저장소 루트(`~/home-iot`)에서 실행합니다. 여러 번 실행해도 안전하게 만들어서(이미 있으면 건너뛰거나 덮어씀) 중간에 실패하면 원인을 고치고 다시 실행하면 됩니다.

| 스크립트 | 실행 위치 | make 명령 | 한 줄 설명 | 가이드 |
| --- | --- | --- | --- | --- |
| `scripts/setup-t1-base.sh` | t1-base | - | 개발 도구 설치 + kubeconfig 복사 | 2-2 |
| `scripts/gen-jwt-keys.sh` | t1-base | `make setup`, `make keys` | JWT 서명키·공개키·Envoy JWT 정책 생성 | 2-4 |
| `scripts/setup-t1-loc-db.sh` | t1-loc-db | - | PostgreSQL 설치 · 외부 접속 허용 · 계정/DB 생성 | 6-1 |
| `scripts/k8s-secrets.sh` | t1-base | `make gitops-secrets` | DB·MQTT 계정, JWT 키를 쿠버네티스 Secret 으로 등록 | 7-5 |
| `scripts/ghcr-pull-secret.sh` | t1-base | `make gitops-secrets` | GHCR 비공개 이미지를 받기 위한 pull Secret 등록 | 7-5 |
| `scripts/argocd-install.sh` | t1-base | `make argocd-install` | Argo CD 설치 + 화면을 LoadBalancer 로 노출 | 7-4 |
| `scripts/argocd-repo-secret.sh` | t1-base | - | 비공개 저장소를 Argo CD 에 등록 | 7-4 |
| `scripts/smoke-test.sh` | t1-base | `make smoke` | 회원가입부터 엘리베이터 도착까지 API 흐름 자동 확인 | 4, 7-6 |
| `scripts/jenkins-up.sh` | t1-base | `make jenkins-up`, `make jenkins-down` | Jenkins 컨테이너 빌드 · 실행 · docker 연결 확인 | 10-3 |
| `mosquitto/entrypoint.sh` | 컨테이너 안 (자동) | - | MQTT 계정 파일을 만들고 mosquitto 실행 | - |
| `scripts/dev-all.js` (.js) | t1-base | `make dev` | 백엔드 5개 + dev-gateway 를 한 터미널에서 watch 모드로 실행 | 3 |
| `tools/dev-gateway/index.js` (.js) | t1-base / 컨테이너 | `make dev`, `make up` | 로컬 개발용 Gateway: 경로 라우팅 + JWT 검증 + `x-user-*` 헤더 | 0-1, 3, 4 |

**setup-t1-base.sh — t1-base 개발 도구 설치**

- 실행: `bash scripts/setup-t1-base.sh` (lab 계정, sudo 비밀번호를 물어봄)
- 하는 일
  - 기본 패키지: git, jq, make, openssl, psql(postgresql-client), mosquitto-clients
  - Docker 공식 저장소에서 Docker · compose · buildx 설치, lab 계정을 docker 그룹에 추가
  - Node.js 22 (NodeSource), kubectl v1.37 (pkgs.k8s.io), GitHub CLI(gh)
  - t1-loc-cp 의 `~/.kube/config` 를 scp 로 복사 (이미 있으면 건너뜀)
  - 마지막에 버전과 `kubectl get nodes` 결과 출력
- 바꿀 수 있는 값: `CP_IP` (기본 10.10.31.11), `K8S_MINOR` (기본 v1.37)
- 끝나면 `newgrp docker` 또는 다시 로그인해야 sudo 없이 docker 를 쓸 수 있음

**gen-jwt-keys.sh — JWT 키 만들기**

- 실행: `make setup` 이 자동 실행, 키를 새로 만들 때 `make keys` (= `FORCE=1`)
- 만드는 파일 (모두 `secrets/`, git 에 올라가지 않음)
  - `jwt-private.pem` : RSA 2048 개인키. auth-service 가 토큰에 서명할 때만 사용
  - `jwt-public.pem` : 공개키. 로컬 dev-gateway 가 토큰을 검증할 때 사용 (서비스는 사용하지 않음)
  - `jwks.json` : 공개키를 JWKS 형식으로 바꾼 것 (`kid: homeiot-1`)
  - `security-policy.yaml` : Envoy Gateway 가 HTTPRoute `api` 의 JWT 를 검증하고 `sub`·`email` claim 을 `x-user-id`·`x-user-email` 헤더로 넘기는 정책 (공개키만 포함)
- 이미 키가 있으면 다시 만들지 않음. 키를 새로 만들었으면 클러스터에도 반영해야 함: `make gitops-secrets` → `kubectl -n homeiot rollout restart deploy` (기존 로그인 토큰은 모두 무효가 됨)

**setup-t1-loc-db.sh — DB 서버 준비**

- 실행: t1-base 에서 보내서 t1-loc-db 에서 실행 (6-1절)
  `DB_PASSWORD=<비밀번호> bash setup-t1-loc-db.sh`
- 하는 일
  - PostgreSQL 이 없으면 설치 (Ubuntu 24.04 기본 = 16)
  - `postgresql.conf` 의 `listen_addresses = '*'` (다른 VM 에서 접속 가능하게)
  - `pg_hba.conf` 에 `host homeiot homeiot 10.10.31.0/24 scram-sha-256` 추가 (같은 줄이 있으면 건너뜀)
  - PostgreSQL 재시작, 계정 `homeiot` 생성(있으면 비밀번호만 변경), DB `homeiot` 생성
- 바꿀 수 있는 값: `DB_NAME`, `DB_USER`, `DB_PASSWORD`(필수), `ALLOW_CIDR`
- 테이블은 만들지 않음 → t1-base 에서 `make db-migrate`

**k8s-secrets.sh — 앱 Secret 등록**

- 실행: `make gitops-secrets` 가 자동 실행 (단독: `bash scripts/k8s-secrets.sh`)
- 읽는 값: `deploy/local.env` (없으면 중단), `secrets/` 의 JWT 키 (없으면 gen-jwt-keys.sh 먼저 실행)
- 하는 일
  - `homeiot` 네임스페이스 생성
  - `homeiot-secrets` : `DB_USER`, `DB_PASSWORD`, `MQTT_USERNAME`, `MQTT_PASSWORD` → 모든 서비스가 환경 변수로 읽음, mosquitto 는 이 값으로 계정 생성
  - `homeiot-jwt` : `jwt-private.pem` (auth-service 만 마운트, 토큰 발급용). 다른 서비스는 키가 없음
- `--dry-run=client | kubectl apply` 방식이라 값을 바꾸고 다시 실행하면 갱신됨. 갱신 후 파드 재시작 필요

**ghcr-pull-secret.sh — GHCR 이미지 pull 권한**

- 실행: `GHCR_USER=sooyeong-lee GHCR_TOKEN=<read:packages PAT> make gitops-secrets`
- 하는 일: `homeiot` 네임스페이스에 docker-registry 타입 Secret `ghcr-pull` 생성. `overlays/gitops/serviceaccount.yaml` 이 default ServiceAccount 에 연결해 두어서 모든 파드가 이 Secret 으로 GHCR 에 로그인
- GHCR 패키지를 Public 으로 바꿨다면 필요 없음

**argocd-install.sh — Argo CD 설치**

- 실행: `make argocd-install` (버전 고정: `ARGOCD_VERSION=v3.x.y make argocd-install`)
- 하는 일
  - `argocd` 네임스페이스 생성, 공식 install.yaml 을 server-side apply 로 적용 (CRD 가 커서 일반 apply 는 실패함)
  - argocd-server, argocd-repo-server 가 준비될 때까지 대기
  - `argocd-server` Service 를 LoadBalancer 로 바꿔 MetalLB IP(10.10.31.100~127 중 하나)를 받음
  - 화면 주소와 admin 초기 비밀번호 출력
- 다시 실행하면 같은 버전으로 덮어씀 (업그레이드도 이 방법)

**argocd-repo-secret.sh — 비공개 저장소 등록**

- 실행: `GITHUB_USER=sooyeong-lee GITHUB_TOKEN=<repo 권한 PAT> bash scripts/argocd-repo-secret.sh`
- 하는 일: `argocd` 네임스페이스에 Secret `home-iot-repo` 를 만들고 `argocd.argoproj.io/secret-type=repository` 라벨을 붙임 → Argo CD 가 저장소 자격증명으로 인식 (화면 Settings → Repositories 에 표시)
- 저장소가 Public 이면 필요 없음. 다른 저장소는 `REPO_URL=…` 로 지정

**smoke-test.sh — 흐름 자동 확인**

- 실행: `make smoke` (compose, `http://localhost:8080`) / `BASE_URL=http://<Gateway IP> make smoke` (클러스터)
- 필요한 것: curl, jq, 시뮬레이터가 떠 있어야 함
- 확인 순서 (하나라도 실패하면 빨간 ✘ 와 응답을 출력하고 멈춤)
1. 회원가입 → 같은 이메일로 다시 가입하면 409
2. 로그인 → 토큰 없이 기기 조회하면 401
3. 조명·엘리베이터 등록, ID 없이 공기청정기 등록 → `purifier-<사용자ID>-NN` 으로 자동 생성되는지 → 시뮬레이터 연결로 online 이 되는지 (최대 30초)
4. 조명 켜기 → 밝기 150(범위 밖) 400 → 조명에 온도 명령 422
5. 상태가 DB 에 저장됐는지, 이력에 COMMAND_SENT · STATE_CHANGED 가 있는지
6. 엘리베이터 3층 호출 202 → 바로 다시 호출 409 → arrived 까지 대기 (최대 20초)
7. 테스트로 만든 기기 삭제 (가입한 테스트 계정 `smoke-<시각>@example.com` 은 남음)

**jenkins-up.sh — Jenkins 실행 (CI 를 Jenkins 로 할 때)**

- 실행: `make jenkins-up` / 중지: `make jenkins-down` (데이터 볼륨 `jenkins_home` 은 남음)
- 하는 일
  - `ci/jenkins/.env` 가 없으면 예제를 복사하고 멈춤, `change-me` 값이 남아 있어도 멈춤
  - 호스트 docker 그룹 GID 를 찾아 `DOCKER_GID` 로 넘김 → 컨테이너의 jenkins 사용자가 t1-base docker 를 쓸 수 있게 함
  - `ci/jenkins` 의 Dockerfile 로 이미지 빌드 후 실행 (포트 8090), 로그인 화면이 뜰 때까지 대기
  - 컨테이너 안에서 `docker version` 으로 docker 연결 확인, 접속 주소 출력
- `.env` 를 바꾼 뒤 다시 실행하면 casc.yaml 이 다시 적용되어 비밀번호 · PAT 가 갱신됨

**mosquitto/entrypoint.sh — MQTT 브로커 시작 (직접 실행하지 않음)**

- docker compose 의 mosquitto 컨테이너가 시작할 때 실행 (클러스터는 `deploy/k8s/base/mosquitto.yaml` 의 ConfigMap 에 같은 내용)
- 하는 일: `MQTT_USERNAME`/`MQTT_PASSWORD` 로 `mosquitto_passwd` 계정 파일 생성 → 권한 설정 → mosquitto 실행
- 비밀번호를 바꾸려면 `.env`(로컬) 또는 `deploy/local.env` + `make gitops-secrets`(클러스터) 후 브로커와 서비스 재시작

**dev-all.js — 백엔드 동시 실행 (참고)**

- `make dev` 가 실행. auth · device · control · telemetry · simulator 를 각각 `npm run dev`(`node --watch --env-file=../../.env`)로, dev-gateway 를 `node --watch --env-file=.env tools/dev-gateway/index.js`(포트 8080, 공개키 `secrets/jwt-public.pem`)로 띄우고, 로그 앞에 색깔 있는 `[서비스명]` 을 붙여 한 화면에 출력. Ctrl+C 로 전부 종료

**tools/dev-gateway — 로컬 개발용 Gateway (참고)**

- 클러스터의 Envoy Gateway 가 하는 일을 로컬에서 똑같이 합니다. 외부 패키지 없이 Node.js 기본 모듈만 씁니다.
  - 경로 규칙: `RULES` 배열 = `deploy/k8s/base/gateway.yaml` 의 HTTPRoute (Exact > 정규식 > 긴 PathPrefix 순)
  - 모든 요청에서 `x-user-*` 헤더 삭제 → 보호 경로(`api`)는 Access 토큰 검증(RS256 서명, `iss=homeiot-auth`, `aud=homeiot`, 만료) → `x-user-id`, `x-user-email` 추가
  - 실패하면 401 (`UNAUTHORIZED` / `TOKEN_EXPIRED`, 공통 에러 형식)
  - 시뮬레이터 이벤트 스트림(SSE)도 그대로 전달
- `make dev`(호스트, :8080)와 `make up`(컨테이너 `gateway`, :8080)에서 쓰고, 클러스터에는 배포하지 않습니다.

### 9-7. 폴더 구조

```
home-iot/
├─ packages/common/        공통 모듈 (config, logger, errors, devices, topics, db, auth, mqtt, service)
├─ services/
│  ├─ Dockerfile           백엔드 공용 (--build-arg SERVICE=…)
│  ├─ auth-service/  device-service/  control-service/  telemetry-service/  simulator/
├─ web/                    Next.js (App Router) + Dockerfile
├─ nginx/                  web.conf(클러스터 web-nginx), Dockerfile
├─ tools/dev-gateway/      로컬 개발용 Gateway (JWT 검증 + 라우팅, make dev · make up)
├─ mosquitto/              브로커 설정
├─ db/init/01_schema.sql   테이블 8개 (스키마 dev)
├─ deploy/
│  ├─ local.env.example
│  ├─ argocd/application.yaml   Argo CD Application
│  └─ k8s/base, k8s/overlays/gitops (Argo CD 가 배포)
├─ scripts/                (9-6절) setup-t1-base, setup-t1-loc-db, gen-jwt-keys, k8s-secrets, ghcr-pull-secret,
│                          argocd-install, argocd-repo-secret, smoke-test, dev-all.js
├─ .github/workflows/ci-cd.yml   테스트 · 빌드 · Trivy · GHCR push · 매니페스트 갱신
├─ Jenkinsfile             같은 파이프라인의 Jenkins 버전 (10절)
├─ ci/jenkins/             Jenkins 이미지 · 플러그인 · JCasC · compose
├─ docker-compose.yml
├─ Makefile                make help
└─ docs/LOCAL_DEV_GUIDE.md
```

---

## 10. GitHub Actions 대신 Jenkins로 CI 하기

7절의 CI(GitHub Actions)를 Jenkins로 바꾸는 방법입니다. **Argo CD로 배포하는 부분(7-4 ~ 7-8)은 그대로** 쓰고, 이미지 빌드·GHCR push·태그 커밋만 Jenkins가 합니다.

### 10-1. 구조

```
개발자 ──PR / merge──▶ GitHub (sooyeong-lee/home-iot)
                           ▲ 2분마다 브랜치·PR 확인 (polling)
                           │
          Jenkins (t1-base, 컨테이너, :8090)   ← Jenkinsfile (저장소 루트)
            1) 준비      태그 sha-xxxxxxx, 태그 갱신 커밋이면 건너뜀
            2) 테스트    npm test · JS 문법 · kustomize 렌더링
            3) 빌드      t1-base docker 로 이미지 7개 빌드 → Trivy(CRITICAL 이면 실패)
            4) push      (main 만) GHCR 에 :sha-xxxxxxx, :latest
            5) 매니페스트 (main 만) overlays/gitops 태그 변경 → main 에 커밋 · push
                           │
                           ▼
          Argo CD (7절과 동일) → 로컬 클러스터 자동 배포
```

| 항목 | GitHub Actions (7절) | Jenkins (10절) |
| --- | --- | --- |
| 파이프라인 정의 | `.github/workflows/ci-cd.yml` | `Jenkinsfile` |
| 실행 위치 | GitHub 서버 | t1-base 의 Jenkins 컨테이너 (빌드는 t1-base docker) |
| 변경 감지 | push · PR 즉시 | 2분마다 GitHub 확인 (t1-base는 사설 IP라 GitHub webhook 을 받을 수 없음) |
| GitHub 인증 | 자동 `GITHUB_TOKEN` | PAT 를 Jenkins 자격증명 `github-token` 으로 등록 |
| 결과 확인 | 저장소 Actions 탭, PR Checks | Jenkins 화면 (`http://10.10.31.20:8090`) |
| Argo CD · GHCR · 매니페스트 | 같음 | 같음 |

추가된 파일:

| 파일 | 역할 |
| --- | --- |
| `Jenkinsfile` | 파이프라인 (Actions 워크플로와 같은 단계) |
| `ci/jenkins/Dockerfile` | Jenkins LTS + docker CLI · Node.js 22 · kubectl · 플러그인 |
| `ci/jenkins/plugins.txt` | 플러그인 목록 (Pipeline, Git, GitHub Branch Source, JCasC 등) |
| `ci/jenkins/casc.yaml` | 관리자 계정 · `github-token` 자격증명 자동 설정 (Configuration as Code) |
| `ci/jenkins/docker-compose.yml` | Jenkins 실행 (8090 포트, t1-base docker.sock 연결) |
| `ci/jenkins/.env.example` | 관리자 비밀번호 · GitHub PAT (복사해서 `.env` 로, git 에 안 올라감) |
| `scripts/jenkins-up.sh` | Jenkins 빌드 · 실행 · 상태 확인 (`make jenkins-up`) |

### 10-2. 사전 준비

**① GitHub PAT** — 7-2절 ③과 같은 화면에서 Tokens (classic) 생성

| 권한(scope) | 쓰는 곳 |
| --- | --- |
| `repo` | 저장소 체크아웃, 태그 커밋을 main 에 push |
| `write:packages` (`read:packages` 포함) | GHCR 에 이미지 push |

브랜치 보호 규칙을 쓰면 이 PAT 의 계정이 main 에 push 할 수 있어야 합니다.

**② t1-base 여유 자원** — Jenkins + 이미지 빌드에 메모리 2GB, 디스크 20GB 정도 여유가 필요합니다. 오래된 이미지는 파이프라인이 끝날 때 정리합니다(72시간 지난 것).

**③ 방화벽** — `sudo ufw status` 가 active면 `sudo ufw allow 8090/tcp`

### 10-3. Jenkins 실행 (t1-base)

```bash
cd ~/home-iot
cp ci/jenkins/.env.example ci/jenkins/.env
vi ci/jenkins/.env
#   JENKINS_ADMIN_PASSWORD=<관리자 비밀번호>
#   JENKINS_URL=http://10.10.31.20:8090/
#   GITHUB_USER=sooyeong-lee
#   GITHUB_TOKEN=<10-2 의 PAT>
make jenkins-up
#   docker 연결 확인: 서버 2x.x.x
#   Jenkins: http://10.10.31.20:8090/
```

브라우저에서 `http://10.10.31.20:8090` → `.env` 의 관리자 계정으로 로그인. 설치 마법사 없이 바로 시작합니다.
**Jenkins 관리 → Credentials** 에 `github-token` 이 있는지 확인합니다.

> PAT 나 비밀번호를 바꾸면 `ci/jenkins/.env` 수정 후 `make jenkins-up` 을 다시 실행합니다 (JCasC 가 다시 적용됨).

### 10-4. 파이프라인 등록 (Multibranch Pipeline, 처음 한 번)

1. Jenkins 첫 화면 → **새로운 Item**
2. 이름 `home-iot` → **Multibranch Pipeline** 선택 → OK
3. **Branch Sources → Add source → GitHub**
   - Credentials: `github-token`
   - Repository HTTPS URL: `https://github.com/sooyeong-lee/home-iot.git` → **Validate** 눌러 `Credentials ok` 확인
   - Behaviours: 기본값 유지 (Discover branches, Discover pull requests from origin)
4. **Build Configuration**: Mode `by Jenkinsfile`, Script Path `Jenkinsfile`
5. **Scan Multibranch Pipeline Triggers**: `Periodically if not otherwise run` 체크 → Interval `2 minutes`
6. **Orphaned Item Strategy**: Discard old items, Max # of old items to keep `10`
7. **Save** → 바로 저장소 검사가 시작되고 `main`, 기능 브랜치, `PR-n` 이 각각 잡으로 생깁니다

### 10-5. GitHub Actions 끄기 (둘 중 하나만)

둘 다 켜 두면 같은 커밋을 두 번 빌드하고, 태그 커밋이 서로 충돌합니다.

```bash
gh workflow disable ci-cd          # 워크플로 비활성화 (파일은 남겨 둠)
gh workflow list --all             # ci-cd  disabled_manually
```

웹: 저장소 → **Actions** → 왼쪽 `ci-cd` → 오른쪽 위 `…` → **Disable workflow**

### 10-6. 동작 확인

1. 기능 브랜치를 push 하고 PR 생성 (9-5절)
2. 2분 안에 Jenkins `home-iot » PR-n` 잡이 실행 → 테스트 · 빌드 · Trivy 까지 초록색 (push 단계는 건너뜀)
3. PR merge → `home-iot » main` 실행 → GHCR push · 매니페스트 갱신까지 진행
4. 저장소에 `chore(deploy): 이미지 sha-xxxxxxx 배포` 커밋이 생김 → 다음 검사 때 Jenkins 가 이 커밋을 빌드하지만 **준비 단계에서 건너뜀** (설명: `매니페스트 갱신 커밋 → 건너뜀`)
5. Argo CD 가 새 태그로 동기화: `make argocd-status`

바로 실행하려면 Jenkins 화면에서 `home-iot` → **Scan Multibranch Pipeline Now**, 또는 `main` 잡 → **지금 빌드**.

Argo CD 설치·Secret·Application 등록은 7-4 ~ 7-6절과 같습니다. 이미 7절로 배포 중이라면 Jenkins 로 바꿔도 Argo CD 쪽은 손댈 것이 없습니다.

### 10-7. 다시 GitHub Actions 로 돌아가기

```bash
gh workflow enable ci-cd
make jenkins-down                  # 또는 Jenkins 화면에서 home-iot 잡 Disable
```

### 10-8. 막혔을 때 (Jenkins)

| 증상 | 확인 | 해결 |
| --- | --- | --- |
| `make jenkins-up` 이 `change-me 값이 남아 있습니다` | `ci/jenkins/.env` | 비밀번호 · PAT 입력 |
| `docker: permission denied … docker.sock` | `docker exec homeiot-jenkins id` 에 docker GID 가 있는지 | `make jenkins-up` 다시 실행 (DOCKER_GID 자동 계산) |
| Validate 가 `Credentials ok` 가 아님 / 저장소 검사 401 | Credentials 의 `github-token` | PAT 만료 · `repo` 권한 확인 → `.env` 수정 후 `make jenkins-up` |
| PR 잡이 생기지 않음 | Multibranch 설정의 Behaviours | `Discover pull requests from origin` 추가, **Scan Multibranch Pipeline Now** |
| GHCR push `denied: permission_denied` | PAT 권한 | `write:packages` 추가 |
| 매니페스트 push `protected branch` / `403` | 브랜치 보호 규칙, PAT `repo` 권한 | PAT 계정이 main 에 push 가능하게 |
| Trivy 단계 실패 | 콘솔 출력의 CRITICAL 표 | 베이스 이미지 · 의존성 버전 올림 (7-9절과 같음) |
| `chore(deploy)` 커밋이 계속 생김 | 같은 sha 로 반복되는지 | 준비 단계 로그의 `skip=` 값 확인, 커밋 메시지가 `chore(deploy):` 로 시작하는지 |
| 빌드가 느리거나 디스크 부족 | `docker system df` | `docker builder prune -f`, `docker image prune -a --filter until=72h` |
