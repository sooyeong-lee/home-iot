#!/usr/bin/env node
'use strict';
/**
 * dev-gateway : 로컬 개발용 API Gateway (클러스터의 Envoy Gateway 역할)
 *
 *  - 경로 규칙은 deploy/k8s/base/gateway.yaml 의 HTTPRoute 와 같다 (바꾸면 둘 다 고칠 것)
 *  - 보호 경로(HTTPRoute 'api')는 Access 토큰(RS256)을 여기서 검증하고
 *    claim 을 헤더로 넣어 전달한다:  sub → x-user-id, email → x-user-email
 *    (Envoy SecurityPolicy 의 jwt + claimToHeaders 와 같은 동작)
 *  - 바깥에서 들어온 x-user-* 헤더는 항상 지운다 (위조 방지)
 *  - 외부 패키지 없이 Node.js 기본 모듈만 사용
 *
 * 환경 변수
 *   PORT (8080), JWT_PUBLIC_KEY_FILE, JWT_ISSUER (homeiot-auth), JWT_AUDIENCE (homeiot)
 *   AUTH_URL, DEVICE_URL, CONTROL_URL, TELEMETRY_URL, SIMULATOR_URL, WEB_URL (기본: localhost 각 포트)
 */
const http = require('node:http');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

const PORT = Number(process.env.PORT || 8080);
const ISSUER = process.env.JWT_ISSUER || 'homeiot-auth';
const AUDIENCE = process.env.JWT_AUDIENCE || 'homeiot';
const keyFile = process.env.JWT_PUBLIC_KEY_FILE;
if (!keyFile) { console.error('JWT_PUBLIC_KEY_FILE 가 필요합니다'); process.exit(1); }
const publicKey = crypto.createPublicKey(fs.readFileSync(path.resolve(process.cwd(), keyFile)));

const up = (name, port) => new URL(process.env[`${name}_URL`] || `http://localhost:${port}`);
const AUTH = up('AUTH', 3001);
const DEVICE = up('DEVICE', 3002);
const CONTROL = up('CONTROL', 3003);
const TELEMETRY = up('TELEMETRY', 3004);
const SIMULATOR = up('SIMULATOR', 3005);
const WEB = up('WEB', 3000);

// ---- 경로 규칙 (gateway.yaml 과 동일) ----
// route: 'api-public' | 'api'(JWT 필요) | 'web'
const RULES = [
  // api-public
  { route: 'api-public', exact: '/api/v1/auth/signup', to: AUTH },
  { route: 'api-public', exact: '/api/v1/auth/login', to: AUTH },
  { route: 'api-public', exact: '/api/v1/auth/refresh', to: AUTH },
  { route: 'api-public', exact: '/api/v1/auth/.well-known/jwks.json', to: AUTH },
  // api (JWT)
  { route: 'api', exact: '/api/v1/auth/logout', to: AUTH },
  { route: 'api', prefix: '/api/v1/users', to: AUTH },
  { route: 'api', regex: /^\/api\/v1\/devices\/[^/]+\/commands$/, to: CONTROL },
  { route: 'api', prefix: '/api/v1/elevator', to: CONTROL },
  { route: 'api', regex: /^\/api\/v1\/devices\/[^/]+\/events$/, to: TELEMETRY },
  { route: 'api', prefix: '/api/v1/devices', to: DEVICE },
  // web
  { route: 'web', prefix: '/simulator', to: SIMULATOR },
  { route: 'web', prefix: '/', to: WEB },
];

// Gateway API PathPrefix: 경로 조각 단위 비교 (/api/v1/devices 는 /api/v1/devicesX 와 맞지 않음)
const prefixMatch = (p, prefix) =>
  prefix === '/' || p === prefix || p.startsWith(prefix.endsWith('/') ? prefix : `${prefix}/`);

/** Envoy 와 같은 우선순위: Exact > RegularExpression > PathPrefix(긴 것 우선) */
function match(pathname) {
  return RULES.find((r) => r.exact === pathname)
    || RULES.find((r) => r.regex && r.regex.test(pathname))
    || RULES.filter((r) => r.prefix && prefixMatch(pathname, r.prefix))
      .sort((a, b) => b.prefix.length - a.prefix.length)[0];
}

// ---- JWT(RS256) 검증 ----
const b64json = (s) => JSON.parse(Buffer.from(s, 'base64url').toString('utf8'));

function verifyJwt(token) {
  const parts = token.split('.');
  if (parts.length !== 3) return { error: 'UNAUTHORIZED' };
  let header; let payload;
  try { header = b64json(parts[0]); payload = b64json(parts[1]); } catch { return { error: 'UNAUTHORIZED' }; }
  if (header.alg !== 'RS256') return { error: 'UNAUTHORIZED' };
  const ok = crypto.verify('RSA-SHA256', Buffer.from(`${parts[0]}.${parts[1]}`), publicKey, Buffer.from(parts[2], 'base64url'));
  if (!ok) return { error: 'UNAUTHORIZED' };
  const now = Math.floor(Date.now() / 1000);
  const aud = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
  if (payload.iss !== ISSUER || !aud.includes(AUDIENCE)) return { error: 'UNAUTHORIZED' };
  if (typeof payload.nbf === 'number' && payload.nbf > now + 30) return { error: 'UNAUTHORIZED' };
  if (typeof payload.exp !== 'number' || payload.exp <= now) return { error: 'TOKEN_EXPIRED' };
  if (!payload.sub) return { error: 'UNAUTHORIZED' };
  return { payload };
}

function reject(res, code) {
  const message = code === 'TOKEN_EXPIRED' ? '토큰이 만료되었습니다.' : '인증이 필요합니다.';
  res.writeHead(401, { 'Content-Type': 'application/json; charset=utf-8', 'WWW-Authenticate': 'Bearer' });
  res.end(JSON.stringify({ success: false, error: { code, message } }));
}

const log = (o) => process.stdout.write(JSON.stringify({ time: new Date().toISOString(), level: 'info', service: 'dev-gateway', ...o }) + '\n');

// ---- 프록시 ----
const server = http.createServer((req, res) => {
  const started = Date.now();
  const url = new URL(req.url, 'http://gateway');
  const rule = match(url.pathname);
  if (!rule) { res.writeHead(404).end(); return; }

  // 위조 방지: 바깥에서 온 사용자 헤더 제거
  const headers = { ...req.headers };
  for (const h of Object.keys(headers)) if (h.startsWith('x-user-')) delete headers[h];

  let userId;
  if (rule.route === 'api') {
    const m = /^Bearer\s+(.+)$/i.exec(req.headers.authorization || '');
    const result = m ? verifyJwt(m[1]) : { error: 'UNAUTHORIZED' };
    if (result.error) {
      log({ msg: 'jwt rejected', method: req.method, path: url.pathname, code: result.error });
      reject(res, result.error);
      return;
    }
    userId = String(result.payload.sub);
    headers['x-user-id'] = userId;
    if (result.payload.email) headers['x-user-email'] = String(result.payload.email);
  }

  headers.host = rule.to.host;
  headers['x-forwarded-for'] = [req.headers['x-forwarded-for'], req.socket.remoteAddress].filter(Boolean).join(', ');
  headers['x-forwarded-host'] = req.headers.host || '';

  const upstream = http.request({
    protocol: rule.to.protocol, hostname: rule.to.hostname, port: rule.to.port,
    method: req.method, path: req.url, headers,
  }, (ur) => {
    res.writeHead(ur.statusCode, ur.headers);
    ur.pipe(res); // SSE(시뮬레이터 이벤트)도 그대로 흘려보냄
    ur.on('end', () => {
      if (!url.pathname.startsWith('/_next')) {
        log({ msg: 'proxy', method: req.method, path: url.pathname, route: rule.route, status: ur.statusCode, userId, durationMs: Date.now() - started });
      }
    });
  });
  upstream.on('error', (err) => {
    log({ msg: 'upstream error', path: url.pathname, upstream: rule.to.host, err: err.code || err.message });
    if (!res.headersSent) {
      res.writeHead(502, { 'Content-Type': 'application/json; charset=utf-8' });
      res.end(JSON.stringify({ success: false, error: { code: 'UPSTREAM_ERROR', message: `${rule.to.host} 에 연결할 수 없습니다.` } }));
    } else res.destroy();
  });
  req.pipe(upstream);
  res.on('close', () => upstream.destroy());
});

server.listen(PORT, () => log({ msg: 'dev-gateway listening', port: PORT }));
for (const sig of ['SIGINT', 'SIGTERM']) process.on(sig, () => server.close(() => process.exit(0)));
