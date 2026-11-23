'use strict';
/**
 * ID 생성 · 엘리베이터 호출 입력 검증 (DB·MQTT 없이 테스트할 수 있도록 index.js 에서 분리)
 */
const crypto = require('node:crypto');

/** 예) cmd-20261120-1a2b3c4d, call-20261120-1a2b3c4d */
const newId = (prefix, now = new Date()) => {
  const d = now.toISOString().slice(0, 10).replace(/-/g, '');
  return `${prefix}-${d}-${crypto.randomBytes(4).toString('hex')}`;
};

/** 엘리베이터 호출 입력 검증. 문제가 있으면 에러 메시지를, 없으면 null 을 돌려준다 */
function validateElevatorCall({ floor, direction } = {}) {
  if (!Number.isInteger(floor) || floor < -10 || floor > 200 || floor === 0) return 'floor 는 -10~200 사이 정수(0 제외)여야 합니다.';
  if (direction !== undefined && direction !== null && !['up', 'down'].includes(direction)) return 'direction 은 up | down 중 하나여야 합니다.';
  return null;
}

module.exports = { newId, validateElevatorCall };
