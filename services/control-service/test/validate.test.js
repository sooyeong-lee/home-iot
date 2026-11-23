'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { newId, validateElevatorCall } = require('../src/validate');

test('ID 형식: <prefix>-<YYYYMMDD>-<hex 8자리>', () => {
  const id = newId('cmd', new Date('2026-11-20T03:00:00Z'));
  assert.match(id, /^cmd-20261120-[0-9a-f]{8}$/);
  assert.notEqual(newId('call'), newId('call'));
});

test('엘리베이터 층 범위: -10 ~ 200, 0 제외, 정수', () => {
  for (const floor of [-10, -1, 1, 200]) assert.equal(validateElevatorCall({ floor }), null, String(floor));
  for (const floor of [0, -11, 201, 1.5, '3', undefined]) assert.match(validateElevatorCall({ floor }), /floor/, String(floor));
});

test('방향은 up | down | 생략', () => {
  assert.equal(validateElevatorCall({ floor: 3, direction: 'up' }), null);
  assert.equal(validateElevatorCall({ floor: 3, direction: null }), null);
  assert.match(validateElevatorCall({ floor: 3, direction: 'left' }), /direction/);
});
