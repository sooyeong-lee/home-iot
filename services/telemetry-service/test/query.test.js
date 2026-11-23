'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { parseEventsQuery } = require('../src/query');

test('기본값: limit 50, 필터 없음', () => {
  assert.deepEqual(parseEventsQuery({}), { fromD: null, toD: null, type: null, limit: 50, error: null });
});

test('limit 은 최대 500, 숫자가 아니면 50', () => {
  assert.equal(parseEventsQuery({ limit: '10' }).limit, 10);
  assert.equal(parseEventsQuery({ limit: '9999' }).limit, 500);
  assert.equal(parseEventsQuery({ limit: 'abc' }).limit, 50);
});

test('from/to 는 ISO 8601', () => {
  const r = parseEventsQuery({ from: '2026-11-01T00:00:00Z', to: '2026-11-20' });
  assert.equal(r.error, null);
  assert.equal(r.fromD.toISOString(), '2026-11-01T00:00:00.000Z');
  assert.match(parseEventsQuery({ from: 'yesterday' }).error, /from\/to/);
});

test('이벤트 종류 검사', () => {
  assert.equal(parseEventsQuery({ type: 'OFFLINE' }).error, null);
  assert.match(parseEventsQuery({ type: 'DELETED' }).error, /type/);
});
