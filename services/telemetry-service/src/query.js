'use strict';
/**
 * 이력 조회 쿼리 파라미터 해석 (DB·MQTT 없이 테스트할 수 있도록 index.js 에서 분리)
 */
const EVENT_TYPES = ['STATE_CHANGED', 'COMMAND_SENT', 'ONLINE', 'OFFLINE'];

/**
 * GET /devices/:deviceId/events 의 from, to, type, limit 해석
 * @returns {{ fromD: Date|null, toD: Date|null, type: string|null, limit: number, error: string|null }}
 */
function parseEventsQuery({ from, to, type, limit } = {}) {
  const lim = Math.min(Number.parseInt(limit ?? '50', 10) || 50, 500);
  const fromD = from ? new Date(from) : null;
  const toD = to ? new Date(to) : null;
  let error = null;
  if ((fromD && Number.isNaN(fromD.getTime())) || (toD && Number.isNaN(toD.getTime()))) error = 'from/to 는 ISO 8601 형식이어야 합니다.';
  else if (type && !EVENT_TYPES.includes(type)) error = 'type 값이 올바르지 않습니다.';
  return { fromD, toD, type: type ?? null, limit: lim, error };
}

module.exports = { EVENT_TYPES, parseEventsQuery };
