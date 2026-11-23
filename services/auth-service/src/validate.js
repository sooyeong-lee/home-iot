'use strict';
/**
 * 입력값 검증 (DB·키 없이 테스트할 수 있도록 index.js 에서 분리)
 */
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/** 회원가입 입력 검증. 문제가 있으면 [{ field, message }] 를, 없으면 빈 배열을 돌려준다 */
function validateSignup({ email, password, name } = {}) {
  const details = [];
  if (typeof email !== 'string' || !EMAIL_RE.test(email) || email.length > 255) details.push({ field: 'email', message: '이메일 형식이 올바르지 않습니다.' });
  if (typeof password !== 'string' || password.length < 8 || password.length > 72) details.push({ field: 'password', message: '비밀번호는 8자 이상(72자 이하)이어야 합니다.' });
  if (typeof name !== 'string' || !name.trim() || name.length > 50) details.push({ field: 'name', message: '이름을 입력하세요 (50자 이하).' });
  return details;
}

module.exports = { EMAIL_RE, validateSignup };
