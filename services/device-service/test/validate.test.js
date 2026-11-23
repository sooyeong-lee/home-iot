'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { nextDeviceIdFrom, validateDeviceInput, DEVICE_ID_RE } = require('../src/validate');
const { DEVICE_TYPES } = require('../../../packages/common/src/devices');

const fields = (d) => d.map((x) => x.field);

test('기기가 없으면 01 부터', () => {
  assert.equal(nextDeviceIdFrom('light', 5, []), 'light-5-01');
});

test('가장 큰 순번 + 1 (중간에 삭제된 번호는 다시 쓰지 않음)', () => {
  assert.equal(nextDeviceIdFrom('light', 5, ['light-5-01', 'light-5-03']), 'light-5-04');
  assert.equal(nextDeviceIdFrom('aircon', 5, ['aircon-5-09']), 'aircon-5-10');
});

test('순번이 아닌 ID 는 무시', () => {
  assert.equal(nextDeviceIdFrom('light', 5, ['light-5-living', 'light-5-02']), 'light-5-03');
});

test('기기 ID 규칙', () => {
  assert.ok(DEVICE_ID_RE.test('light-living-01'));
  for (const bad of ['ab', 'Light-01', '-light', 'light_01', 'a'.repeat(51)]) assert.ok(!DEVICE_ID_RE.test(bad), bad);
});

test('deviceId 를 안 보내면 자동 생성', () => {
  for (const deviceId of [undefined, null, '']) {
    assert.deepEqual(validateDeviceInput({ deviceId, name: '거실 조명', type: 'light' }, DEVICE_TYPES), { auto: true, details: [] });
  }
});

test('deviceId 를 보내면 형식 검사', () => {
  const r = validateDeviceInput({ deviceId: 'BAD ID', name: '조명', type: 'light' }, DEVICE_TYPES);
  assert.equal(r.auto, false);
  assert.deepEqual(fields(r.details), ['deviceId']);
});

test('이름 · 종류 · 위치 검사', () => {
  const r = validateDeviceInput({ name: '', type: 'toaster', location: 'a'.repeat(51) }, DEVICE_TYPES);
  assert.deepEqual(fields(r.details), ['name', 'type', 'location']);
});
