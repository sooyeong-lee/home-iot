'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { nextFloor } = require('../src/elevator');

test('목표 층 방향으로 한 층씩 이동', () => {
  assert.equal(nextFloor(1, 5), 2);
  assert.equal(nextFloor(5, 1), 4);
});

test('도착했으면 그대로', () => {
  assert.equal(nextFloor(3, 3), 3);
});

test('0층은 건너뛴다', () => {
  assert.equal(nextFloor(1, -2), -1);
  assert.equal(nextFloor(-1, 3), 1);
});

test('대시보드 화면 파일이 src/public 에 있다', () => {
  assert.ok(fs.existsSync(path.join(__dirname, '..', 'src', 'public', 'index.html')));
});
