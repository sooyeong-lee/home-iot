# Home IoT

가정 전자기기 IoT 연동 시스템 (MSA) — 조명 · 에어컨 · 난방기기 · 공기청정기 · 커튼 · 엘리베이터 호출

Next.js · Nginx · Node.js/Express · MQTT(Mosquitto) · PostgreSQL · REST API · JWT · Envoy Gateway

| 서비스 | 포트 | 역할 |
| --- | --- | --- |
| auth-service | 3001 | 회원가입 · 로그인 · JWT |
| device-service | 3002 | 기기 등록 · 조회 |
| control-service | 3003 | 명령 발행 · 응답 처리 · 엘리베이터 호출 |
| telemetry-service | 3004 | 상태 구독 · 이력 저장 |
| simulator | 3005 | 가전 기기 시뮬레이터 (/simulator) |
| web | 3000 | 사용자 화면 (Next.js) |

## 빠른 시작 (t1-base)

```bash
unzip home-iot.zip && cd home-iot                  # 전달받은 소스
bash scripts/setup-t1-base.sh && newgrp docker   # 처음 한 번
git init -b main && git add -A && git commit -m "feat: 초기 소스"
git remote add origin https://github.com/sooyeong-lee/home-iot.git   # 올리기: 가이드 2-3절
make setup                                        # .env, JWT 키, npm install
make infra                                        # postgres + mosquitto
make dev                                          # 백엔드 5개 (watch)
make web-dev                                      # http://<t1-base>:3000
```

전부 컨테이너로: `make up` → `http://<t1-base>:8080`, 확인: `make smoke`

로컬 클러스터 배포: Jenkins → GHCR → Argo CD (main 에 merge 하면 자동 배포, 가이드 7절). GitHub Actions 버전은 참고용(가이드 10절)

자세한 절차는 **[docs/LOCAL_DEV_GUIDE.md](docs/LOCAL_DEV_GUIDE.md)**, 명령 목록은 `make help`.
