'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { validateSignup } = require('../src/validate');

const fields = (d) => d.map((x) => x.field);

test('올바른 회원가입 입력은 통과', () => {
  assert.deepEqual(validateSignup({ email: 'a@b.co', password: '12345678', name: '홍길동' }), []);
});

test('이메일 형식 오류', () => {
  for (const email of ['', 'abc', 'a@b', 'a b@c.d', 123, undefined]) {
    assert.deepEqual(fields(validateSignup({ email, password: '12345678', name: 'x' })), ['email']);
  }
});

test('비밀번호는 8~72자', () => {
  assert.deepEqual(fields(validateSignup({ email: 'a@b.co', password: '1234567', name: 'x' })), ['password']);
  assert.deepEqual(fields(validateSignup({ email: 'a@b.co', password: 'a'.repeat(73), name: 'x' })), ['password']);
  assert.deepEqual(validateSignup({ email: 'a@b.co', password: 'a'.repeat(72), name: 'x' }), []);
});

test('이름은 공백만 있으면 안 되고 50자 이하', () => {
  assert.deepEqual(fields(validateSignup({ email: 'a@b.co', password: '12345678', name: '   ' })), ['name']);
  assert.deepEqual(fields(validateSignup({ email: 'a@b.co', password: '12345678', name: 'a'.repeat(51) })), ['name']);
});

test('여러 항목이 틀리면 모두 알려준다', () => {
  assert.deepEqual(fields(validateSignup({})), ['email', 'password', 'name']);
});
