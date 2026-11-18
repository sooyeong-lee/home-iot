#!/usr/bin/env node
'use strict';
/**
 * 백엔드 서비스 5개 + 개발용 게이트웨이를 한 터미널에서 watch 모드로 실행 (npm run dev:services)
 * 게이트웨이(:8080)가 JWT 를 검증하고 x-user-id 를 붙여 각 서비스로 전달한다.
 * 각 줄 앞에 [서비스명] 을 붙여 출력한다. Ctrl+C 로 모두 종료.
 */
const { spawn } = require('node:child_process');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const services = ['auth-service', 'device-service', 'control-service', 'telemetry-service', 'simulator', 'dev-gateway'];
const colors = [31, 32, 33, 34, 35, 36];
const commands = {
  'dev-gateway': {
    cmd: process.execPath,
    args: ['--watch', '--env-file=.env', 'tools/dev-gateway/index.js'],
    env: { ...process.env, JWT_PUBLIC_KEY_FILE: 'secrets/jwt-public.pem', PORT: '8080' },
  },
};
const children = services.map((name, i) => {
  const c = commands[name] ?? { cmd: 'npm', args: ['run', 'dev', '-w', `services/${name}`, '--silent'], env: process.env };
  const child = spawn(c.cmd, c.args, { cwd: root, env: c.env });
  const prefix = `\x1b[${colors[i]}m[${name}]\x1b[0m `;
  const pipe = (stream, out) => {
    let buf = '';
    stream.on('data', (chunk) => {
      buf += chunk;
      const lines = buf.split('\n');
      buf = lines.pop();
      for (const l of lines) out.write(prefix + l + '\n');
    });
  };
  pipe(child.stdout, process.stdout);
  pipe(child.stderr, process.stderr);
  child.on('exit', (code) => process.stdout.write(`${prefix}종료 (code ${code})\n`));
  return child;
});

const stop = () => { children.forEach((c) => c.kill('SIGTERM')); setTimeout(() => process.exit(0), 500); };
process.on('SIGINT', stop);
process.on('SIGTERM', stop);
